# frozen_string_literal: true

module Formsmith
  # The binding information owned by Rails and presented to an adapter.
  class Field
    attr_reader :object, :attribute, :name, :id, :value, :errors, :label

    def initialize(object:, attribute:, name:, id:, value:, errors:, label:, value_supplied: false)
      @object = object
      @attribute = attribute
      @name = name
      @id = id
      @value = value
      @errors = errors.freeze
      @label = label
      @value_supplied = value_supplied
      freeze
    end

    def value_supplied?
      @value_supplied
    end
  end
end
