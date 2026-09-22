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

class FormsmithRawComponent < ViewComponent::Base
  def initialize(arguments:, options:)
    @arguments, @options = arguments, options
  end

  def call
    tag.button(content.presence || @arguments.first || "Save", **@options)
  end
end

class FormsmithRawAdapter
  class << self
    attr_accessor :arguments, :options
  end

  def self.build(arguments:, options:)
    self.arguments, self.options = arguments, options
    FormsmithRawComponent.new(arguments: arguments, options: options)
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

  def configured_builder(**registration)
    Class.new(FormsmithSpecBuilder) do
      register :text_field, adapter: FormsmithCapturingAdapter, replace: true, **registration
    end
  end

  def capture_options(builder:, defaults:, defaults_merge: :shallow, **options)
    render_form(:user, User.new, builder: builder, defaults: defaults, defaults_merge: defaults_merge) do |form|
      form.text_field(:email, **options)
    end
    FormsmithCapturingAdapter.options
  end

  it "binds missing model readers without requiring an attribute declaration" do
    builder = configured_builder
    render_form(:user, User.new, builder: builder) { |form| form.text_field(:image_owner) }
    field = FormsmithCapturingAdapter.field
    expect([field.name, field.id, field.value, field.label, field.errors]).to eq(
      ["user[image_owner]", "user_image_owner", nil, "Image owner", []]
    )
    expect(field.value_supplied?).to be(false)
    ["Alice", nil, false].each do |value|
      render_form(:user, User.new, builder: builder) { |form| form.text_field(:image_owner, value: value) }
      expect(FormsmithCapturingAdapter.field.value).to eq(value)
      expect(FormsmithCapturingAdapter.field.value_supplied?).to be(true)
    end
  end

  it "keeps binding overrides only on the resolved field" do
    options = capture_options(builder: configured_builder, defaults: { value: "default" },
      name: "custom", id: "custom-id", value: nil, label: false, errors: nil, class: "input")
    expect(options).to eq(class: "input")
    field = FormsmithCapturingAdapter.field
    expect([field.name, field.id, field.value, field.label, field.errors]).to eq(["custom", "custom-id", nil, false, []])
  end

  it "uses shallow replacement by default" do
    expect(capture_options(builder: configured_builder,
      defaults: { data: { controller: "field" } }, data: { action: "change" }
    )).to eq(data: { action: "change" })
  end

  it "deep merges hashes while replacing arrays, strings, nil, and false" do
    defaults = { data: { controller: "field", action: "blur" }, class: "input", choices: [1], disabled: true, title: "Title" }
    options = capture_options(builder: configured_builder, defaults: defaults, defaults_merge: :deep,
      data: { action: "change" }, class: "large", choices: [2], disabled: false, title: nil)
    expect(options).to eq(data: { controller: "field", action: "change" }, class: "large", choices: [2], disabled: false, title: nil)
    expect(defaults[:data]).to eq(controller: "field", action: "blur")
  end

  it "inherits builder policies and lets forms and registrations override them" do
    parent = configured_builder
    parent.defaults_merge :deep
    child = Class.new(parent)
    render_form(:user, User.new, builder: child, defaults: { data: { controller: "field" } }) do |form|
      form.text_field(:email, data: { action: "change" })
    end
    expect(FormsmithCapturingAdapter.options[:data]).to eq(controller: "field", action: "change")
    expect(capture_options(builder: child, defaults: { data: { controller: "field" } },
      defaults_merge: :shallow, data: { action: "change" })).to eq(data: { action: "change" })
    child.register :text_field, adapter: FormsmithCapturingAdapter, replace: true, merge: :deep
    expect(capture_options(builder: child, defaults: { data: { controller: "field" } },
      defaults_merge: :shallow, data: { action: "change" })).to eq(data: { controller: "field", action: "change" })
    child.defaults_merge :shallow
    expect(parent.defaults_merge).to eq(:deep)
    expect(parent.registration_options[:text_field][:merge]).to be_nil
  end

  it "inherits nested merge policies and permits replacement or clearing of defaults" do
    builder = configured_builder
    render_form(:user, User.new, builder: builder, defaults_merge: :deep, defaults: { data: { controller: "field" } }) do |form|
      form.fields_for(:profile, User.new) do |nested|
        nested.text_field(:email, data: { action: "change" })
      end
    end
    expect(FormsmithCapturingAdapter.options).to eq(data: { controller: "field", action: "change" })
    [{ defaults_merge: :shallow }, { defaults: {} }].each do |nested_options|
      render_form(:user, User.new, builder: builder, defaults_merge: :deep, defaults: { data: { controller: "field" } }) do |form|
        form.fields_for(:profile, User.new, nested_options) do |nested|
          nested.text_field(:email, data: { action: "change" })
        end
      end
      expect(FormsmithCapturingAdapter.options).to eq(data: { action: "change" })
    end
  end

  it "lets adapters merge both original sources before resolving binding overrides" do
    adapter = Class.new(FormsmithCapturingAdapter) do
      def self.merge_options(defaults:, options:)
        merged = defaults.deep_merge(options)
        merged[:class] = [defaults[:class], options[:class]].join(" ")
        merged[:value] = "merged value"
        defaults[:data][:controller].replace("mutated")
        options[:data][:action].replace("mutated")
        merged
      end
    end
    builder = Class.new(FormsmithSpecBuilder)
    builder.register :text_field, adapter: adapter, replace: true, merge: :adapter
    defaults = { class: "input", data: { controller: "field" } }
    options = { class: "large", data: { action: "change" } }
    render_form(:user, User.new, builder: builder, defaults: defaults) { |form| form.text_field(:email, options) }
    expect(adapter.options[:class]).to eq("input large")
    expect(adapter.field.value).to eq("merged value")
    expect(adapter.options).not_to have_key(:value)
    expect(defaults).to eq(class: "input", data: { controller: "field" })
    expect(options).to eq(class: "large", data: { action: "change" })
  end

  it "reports invalid configuration and adapter merge contracts" do
    builder = configured_builder
    expect { builder.defaults_merge :combine }.to raise_error(ArgumentError, /merge policy/)
    expect { builder.register :custom, adapter: FormsmithSpecAdapter, merge: :combine }.to raise_error(ArgumentError, /merge policy/)
    expect { builder.register :custom, adapter: FormsmithSpecAdapter, arguments: :unknown }.to raise_error(ArgumentError, /arguments/)
    expect { capture_options(builder: builder, defaults: {}, defaults_merge: nil) }.to raise_error(ArgumentError, /merge policy/)
    expect { capture_options(builder: builder, defaults: {}, defaults_merge: :adapter) }.to raise_error(ArgumentError, /must implement merge_options/)
    adapter = Class.new(FormsmithCapturingAdapter) do
      def self.merge_options(defaults:, options:) = nil
    end
    builder.register :text_field, adapter: adapter, replace: true, merge: :adapter
    expect { capture_options(builder: builder, defaults: {}) }.to raise_error(ArgumentError, /must return a Hash/)
  end

  it "registers submit and button with raw arguments, intact options, and render blocks" do
    builder = Class.new(FormsmithSpecBuilder) do
      register :submit, adapter: FormsmithRawAdapter, arguments: :raw
      register :button, adapter: FormsmithRawAdapter, arguments: :raw
    end
    html = render_form(:user, User.new, builder: builder, defaults: { class: "primary" }) do |form|
      form.submit("Save invoice", name: "commit", value: "save", id: "save")
    end
    expect(html).to include('name="commit"', 'value="save"', 'id="save"', 'class="primary"', 'Save invoice')
    expect(FormsmithRawAdapter.arguments).to eq(["Save invoice"])
    render_form(:user, User.new, builder: builder) { |form| form.submit }
    expect(FormsmithRawAdapter.arguments).to eq([])
    html = render_form(:user, User.new, builder: builder) { |form| form.button("ignored") { "Block label" } }
    expect(html).to include("Block label")
  end

  it "supports multiple raw arguments and merges a trailing options hash with keywords" do
    builder = Class.new(FormsmithSpecBuilder) do
      register :date_range, adapter: FormsmithRawAdapter, arguments: :raw, merge: :deep
    end
    render_form(:user, User.new, builder: builder, defaults: { data: { controller: "range" } }) do |form|
      form.date_range(:starts_on, :ends_on, { class: "old", label: false }, class: "new", data: { action: "change" })
    end
    expect(FormsmithRawAdapter.arguments).to eq([:starts_on, :ends_on])
    expect(FormsmithRawAdapter.options).to eq(class: "new", label: false, data: { controller: "range", action: "change" })
  end

  it "allows label and hidden field adapters while protecting structural helpers" do
    builder = configured_builder
    %i[label hidden_field].each do |method|
      builder.register method, adapter: FormsmithCapturingAdapter
      render_form(:user, User.new, builder: builder) { |form| form.public_send(method, :email) }
      expect(FormsmithCapturingAdapter.field.attribute).to eq(:email)
    end
    %i[fields fields_for object object_name options multipart? multipart= id field_name field_id].each do |method|
      expect { builder.register method, adapter: FormsmithSpecAdapter }.to raise_error(ArgumentError, /reserved/)
    end
  end

  it "rejects positional field signatures instead of silently dropping arguments" do
    expect { render_form { |form| form.select(:email, ["AU", "NZ"]) } }.to raise_error(ArgumentError, /one field name/)
  end

  it "keeps validation errors for fields without readers and handles forms without a model" do
    user = User.new
    allow(user.errors).to receive(:full_messages_for).with(:image_owner).and_return(["Image owner is required"])
    builder = configured_builder
    render_form(:user, user, builder: builder) { |form| form.text_field(:image_owner) }
    expect(FormsmithCapturingAdapter.field.errors).to eq(["Image owner is required"])
    render_form(:search, false, builder: builder) { |form| form.text_field(:query) }
    field = FormsmithCapturingAdapter.field
    expect([field.name, field.value, field.label, field.errors]).to eq(["search[query]", nil, "Query", []])
  end

  it "runs adapter merging for raw registrations without removing binding-named options" do
    adapter = Class.new(FormsmithRawAdapter) do
      def self.merge_options(defaults:, options:)
        defaults.deep_merge(options).merge(value: "merged", label: "Caption")
      end
    end
    builder = Class.new(FormsmithSpecBuilder)
    builder.register :submit, adapter: adapter, arguments: :raw, merge: :adapter
    render_form(:user, User.new, builder: builder, defaults: { data: { controller: "submit" } }) do |form|
      form.submit("Save", data: { action: "click" })
    end
    expect(adapter.options).to eq(data: { controller: "submit", action: "click" }, value: "merged", label: "Caption")
  end

  it "keeps inherited raw registrations independent when replaced with field registrations" do
    parent = Class.new(FormsmithSpecBuilder)
    parent.register :custom, adapter: FormsmithRawAdapter, arguments: :raw, merge: :deep
    child = Class.new(parent)
    child.register :custom, adapter: FormsmithCapturingAdapter, replace: true
    render_form(:user, User.new, builder: child) { |form| form.custom(:email) }
    expect(FormsmithCapturingAdapter.field.attribute).to eq(:email)
    render_form(:user, User.new, builder: parent) { |form| form.custom("Caption") }
    expect(FormsmithRawAdapter.arguments).to eq(["Caption"])
    expect(parent.registration_options[:custom]).to eq(arguments: :raw, merge: :deep)
  end

end
