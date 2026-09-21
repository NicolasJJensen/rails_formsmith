# frozen_string_literal: true

require "bundler/setup"
require "erb"
require "rails"
require "action_controller/railtie"
require "active_model"
require "view_component"
require "view_component/engine"

class FormsmithTestApplication < Rails::Application
  config.eager_load = false
  config.secret_key_base = "formsmith-test-secret"
end

FormsmithTestApplication.initialize!
require "rspec/rails"
require "view_component/test_helpers"
require "formsmith"

RSpec.configure do |config|
  config.include ViewComponent::TestHelpers
  config.use_active_record = false
end
