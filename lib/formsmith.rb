# frozen_string_literal: true

require "action_view"
require "active_support/core_ext/hash/except"
require "active_support/core_ext/object/deep_dup"
require "active_support/core_ext/string/inflections"
require "view_component"
require_relative "formsmith/version"
require_relative "formsmith/field"
require_relative "formsmith/builder"

module Formsmith
end
