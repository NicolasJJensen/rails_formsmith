# frozen_string_literal: true

require "spec_helper"

class FormsmithSpecAdapter
  def self.build(field:, options:)
    FormsmithSpecComponent.new(field:, options:)
  end
end

class FormsmithSpecReplacementAdapter < FormsmithSpecAdapter; end

class FormsmithCapturingAdapter < FormsmithSpecAdapter
  class << self
    attr_accessor :field, :options
  end

  def self.build(field:, options:)
    self.field = field
    self.options = options
    super
  end
end

class FormsmithMutatingAdapter < FormsmithSpecAdapter
  def self.build(field:, options:)
    options[:data][:adapter] = "mutated"
    super
  end
end

class FormsmithSpecComponent < ViewComponent::Base
  attr_reader :field, :options

  def initialize(field:, options:)
    @field = field
    @options = options
  end

  def call
    content_tag(:output, "#{field.name}|#{field.id}|#{field.value.inspect}|#{field.label}|#{field.errors.join(',')}|#{content}")
  end
end

class FormsmithSpecBuilder < Formsmith::Builder
  register :text_field, adapter: "FormsmithSpecAdapter"
  register :select, adapter: FormsmithSpecAdapter
  register :check_box, adapter: FormsmithCapturingAdapter
  register :number_field, adapter: FormsmithMutatingAdapter
  register :file_field, adapter: FormsmithCapturingAdapter
end

RSpec.describe Formsmith::Builder, type: :helper do
  User = Struct.new(:email, :age) do
    include ActiveModel::Conversion

    def persisted? = false

    def model_name = self.class.model_name

    def profiles_attributes=(_attributes); end

    def profiles
      @profiles ||= []
    end

    def self.model_name
      ActiveModel::Name.new(self, nil, "User")
    end
    def self.human_attribute_name(attribute, default:)
      attribute == :email ? "Email address" : default
    end

    def errors
      @errors ||= Class.new do
        def full_messages_for(attribute)
          attribute == :email ? ["Email address is invalid"] : []
        end
      end.new
    end
  end

  def render_form(object_name = :user, object = User.new("a@example.test", 12), options = {})
    helper.form_with(model: object, scope: object_name, url: "/", builder: FormsmithSpecBuilder, **options) do |form|
      yield form
    end
  end

  it "passes Rails binding, labels and errors to a string-resolved adapter" do
    html = render_form { |form| form.text_field(:email) }
    expect(html).to include("user[email]|user_email|&quot;a@example.test&quot;|Email address|Email address is invalid")
  end

  it "keeps false, nil and caller option hashes intact" do
    options = { value: false, label: nil, errors: nil, multiple: true }
    html = render_form { |form| form.text_field(:email, options) }
    expect(html).to include("user[email][]|user_email|false||")
    expect(options).to eq(value: false, label: nil, errors: nil, multiple: true)
  end

  it "uses caller id and name overrides" do
    html = render_form { |form| form.text_field(:email, id: "email-input", name: "account[email]") }
    expect(html).to include("account[email]|email-input")
  end

  it "uses FormBuilder binding helpers for namespaced fields" do
    html = render_form(:user, User.new, namespace: :settings) { |form| form.text_field(:email) }

    expect(html).to include("user[email]|settings_user_email")
  end

  it "leaves unregistered Rails helpers alone" do
    html = render_form { |form| form.text_area(:email) }
    expect(html).to include("textarea")
    expect(html).to include('name="user[email]"')
  end

  it "passes select keyword choices to the adapter as component options" do
    html = render_form { |form| form.select(:email, options: ["AU", "NZ"]) }
    expect(html).to include("user[email]")
  end

  it "forwards the original render block into the ViewComponent once" do
    html = render_form { |form| form.text_field(:email) { "field slot" } }
    expect(html).to include("field slot")
  end

  it "uses Rails nested names and IDs and inherits form defaults" do
    profile = User.new("profile@example.test", 12)
    html = render_form(:user, User.new, defaults: { label: "Profile email" }) do |form|
      form.fields_for(:profile, profile) { |nested| nested.text_field(:email) }
    end
    expect(html).to include("user[profile][email]|user_profile_email|&quot;profile@example.test&quot;|Profile email")
  end

  it "uses Rails namespace and child-index binding" do
    profile = User.new("profile@example.test", 12)
    user = User.new
    user.profiles << profile
    html = render_form(:user, user) do |form|
      form.fields_for(:profiles, profile, child_index: 7) { |nested| nested.text_field(:email) }
    end
    expect(html).to include("user[profiles_attributes][7][email]|user_profiles_attributes_7_email")
  end

  it "keeps collection binding and explicit checked values separate" do
    html = render_form { |form| form.check_box(:email, multiple: true, checked: "0") }

    expect(html).to include("user[email][]|user_email")
    expect(FormsmithCapturingAdapter.field.value).to eq("a@example.test")
    expect(FormsmithCapturingAdapter.options).to include(multiple: true, checked: "0")
  end

  it "marks forms multipart and creates collection names for file fields" do
    html = render_form { |form| form.file_field(:email, multiple: true) }

    expect(html).to include('enctype="multipart/form-data"')
    expect(html).to include("user[email][]|user_email|nil")
  end

  it "deeply isolates nested component options from adapter mutation" do
    options = {data: {controller: "field"}}
    render_form { |form| form.number_field(:age, options) }

    expect(options).to eq(data: {controller: "field"})
  end

  it "has independent inherited registrations and requires replacement" do
    child = Class.new(FormsmithSpecBuilder)
    expect { child.register(:text_field, adapter: FormsmithSpecReplacementAdapter) }.to raise_error(ArgumentError, /replace/)
    child.register(:text_field, adapter: FormsmithSpecReplacementAdapter, replace: true)
    expect(child.registry[:text_field]).to eq(FormsmithSpecReplacementAdapter)
    expect(FormsmithSpecBuilder.registry[:text_field]).to eq("FormsmithSpecAdapter")
  end

  it "refuses structural registrations" do
    expect { FormsmithSpecBuilder.register(:fields_for, adapter: FormsmithSpecAdapter) }.to raise_error(ArgumentError, /structural/)
  end

  it "applies defaults locally and explicit nil overrides them" do
    html = render_form(:user, User.new, defaults: { label: "Default", value: "default" }) { |form| form.text_field(:email, label: nil, value: nil) }
    expect(html).to include("user[email]|user_email|nil||Email address is invalid")
  end
  it "resolves replacement adapter constants on every render" do
    render_form { |form| form.text_field(:email) }
    replacement = Class.new do
      def self.build(field:, options:)
        FormsmithSpecComponent.new(field: Formsmith::Field.new(
          object: field.object, attribute: field.attribute, name: field.name,
          id: field.id, value: "reloaded", label: field.label, errors: []), options: options)
      end
    end
    stub_const("FormsmithSpecAdapter", replacement)
    expect(render_form { |form| form.text_field(:email) }).to include("reloaded")
  end

end
