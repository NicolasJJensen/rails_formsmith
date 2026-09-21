# frozen_string_literal: true

module Formsmith
  class Builder < ActionView::Helpers::FormBuilder
    RESERVED_HELPERS = %i[
      fields_for fields fields model_name object object_name options
      multipart? id label hidden_field button submit
    ].freeze
    OMITTED = Object.new.freeze
    BINDING_OPTIONS = %i[name id value errors label].freeze

    class << self
      def registry
        @registry ||= superclass.respond_to?(:registry) ? superclass.registry.dup : {}
      end

      def inherited(subclass)
        super
        subclass.instance_variable_set(:@registry, registry.dup)
      end

      def register(method, adapter:, replace: false)
        method = method.to_sym
        if RESERVED_HELPERS.include?(method)
          raise ArgumentError, "#{method} is a structural or reserved FormBuilder helper and cannot be registered"
        end
        if registry.key?(method) && !replace
          raise ArgumentError, "#{method} is already registered; pass replace: true to replace its adapter"
        end

        registry[method] = adapter
        define_component_method(method)
      end

      private

      def define_component_method(method)
        define_method(method) do |attribute, options = {}, &block|
          component_field(method, attribute, options, &block)
        end
      end
    end

    attr_reader :component_defaults

    def initialize(object_name, object, template, options)
      super
      supplied_defaults = options.fetch(:defaults, {})
      unless supplied_defaults.respond_to?(:to_hash)
        raise ArgumentError, "defaults must be a hash"
      end
      @component_defaults = supplied_defaults.to_hash.deep_dup.freeze
    end

    # Rails uses this method for nested attributes. Preserve this builder's
    # scoped defaults unless the nested form explicitly supplies its own.
    def fields_for(record_name, record_object = nil, fields_options = nil, &block)
      if record_object.is_a?(Hash) && fields_options.nil?
        fields_options = record_object
        record_object = nil
      end
      fields_options = (fields_options || {}).dup
      fields_options[:defaults] = component_defaults unless fields_options.key?(:defaults)
      super(record_name, record_object, fields_options, &block)
    end

    private

    def component_field(helper, attribute, supplied_options, &block)
      options = supplied_options.to_hash.deep_dup
      self.multipart = true if helper == :file_field
      adapter = resolve_adapter(self.class.registry.fetch(helper))
      merged_options = component_defaults.deep_dup.merge(options)
      field = build_field(helper, attribute, merged_options)
      component_options = merged_options.except(*BINDING_OPTIONS).deep_dup
      component = adapter.build(field: field, options: component_options)
      @template.render(component, &block)
    end

    def resolve_adapter(adapter)
      return adapter unless adapter.is_a?(String) || adapter.is_a?(Symbol)

      adapter.to_s.constantize
    rescue NameError => error
      raise NameError, "Could not resolve Formsmith adapter #{adapter.inspect}: #{error.message}"
    end

    def build_field(helper, attribute, options)
      attribute = attribute.to_sym
      multiple = options[:multiple]
      name = option_or_generated(options, :name) do
        field_name(attribute, multiple: multiple)
      end
      id = option_or_generated(options, :id) do
        field_id(attribute)
      end

      Field.new(
        object: @object,
        attribute: attribute,
        name: name,
        id: id,
        value: field_value(helper, attribute, options),
        errors: field_errors(attribute, options),
        label: field_label(attribute, options),
        value_supplied: options.key?(:value)
      )
    end

    def option_or_generated(options, key)
      return options[key] if options.key?(key)

      yield
    end

    def field_value(helper, attribute, options)
      return options[:value] if options.key?(:value)
      return nil if %i[password_field file_field].include?(helper)
      return nil unless @object && @object.respond_to?(attribute)

      before_type_cast = "#{attribute}_before_type_cast"
      @object.respond_to?(before_type_cast) ? @object.public_send(before_type_cast) : @object.public_send(attribute)
    end

    def field_errors(attribute, options)
      return normalize_errors(options[:errors]) if options.key?(:errors)
      return [] unless @object&.respond_to?(:errors)

      normalize_errors(@object.errors.full_messages_for(attribute))
    end

    def normalize_errors(errors)
      Array(errors).compact
    end

    def field_label(attribute, options)
      return options[:label] if options.key?(:label)
      return attribute.to_s.humanize unless @object

      @object.class.human_attribute_name(attribute, default: attribute.to_s.humanize)
    end
  end
end
