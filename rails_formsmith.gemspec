# frozen_string_literal: true

require_relative "lib/formsmith/version"

Gem::Specification.new do |spec|
  spec.name = "rails_formsmith"
  spec.version = Formsmith::VERSION
  spec.authors = ["Nicolas J Jensen"]
  spec.email = ["nicolasjensen9@gmail.com"]
  spec.summary = "A small Rails form builder adapter for ViewComponents"
  spec.description = "Formsmith::Builder maps selected Rails form helpers to adapters that return ViewComponents. " \
    "Each registered helper hands its adapter a frozen Field with the binding Rails owns: object, attribute, " \
    "name, id, value, errors, and label. Unregistered helpers keep normal Rails behavior. The builder never " \
    "installs itself as an application default form builder."
  spec.license = "MIT"
  spec.homepage = "https://github.com/NicolasJJensen/rails_formsmith"
  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues"
  }
  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*", "README.md", "CHANGELOG.md", "LICENSE.txt"].select { |f| File.file?(f) }
  end
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 3.2"
  spec.add_dependency "actionview", ">= 7.1", "< 9.0"
  spec.add_dependency "activesupport", ">= 7.1", "< 9.0"
  spec.add_dependency "view_component", ">= 4.0", "< 5.0"
end
