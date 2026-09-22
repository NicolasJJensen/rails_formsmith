# Rails Formsmith

Use your own ViewComponents through Rails form helpers. Formsmith supplies model
values, field names, IDs, labels, and validation errors so your components can
focus on rendering.

You provide the components and small adapters that connect them to a
`Formsmith::Builder` subclass. Choose that builder with `form_with`; helpers you
haven't registered continue to use Rails' normal rendering.

## Requirements

- Ruby 3.2+
- Rails 7.1 through 8.x, with a Ruby version supported by your Rails version
- ViewComponent 4.x

The [compatibility workflow](.github/workflows/compatibility.yml) covers Rails
7.1, 7.2, 8.0, and 8.1.

## Installation

Add the gem to your application's Gemfile:

```ruby
gem "rails_formsmith"
```

Then run `bundle install`.

## Quick start

This example assumes your application has an `Invoice` model with a `reference`
attribute and an `@invoice` instance available in the view.

### 1. Create a component

Add `app/components/text_field_component.rb`:

```ruby
class TextFieldComponent < ViewComponent::Base
  def initialize(name:, id:, value:, label:, errors:, **options)
    @name, @id, @value = name, id, value
    @label, @errors, @options = label, errors, options
  end

  def call
    tag.div do
      safe_join([
        (@label ? tag.label(@label, for: @id) : nil),
        tag.input(**@options, type: "text", name: @name, id: @id, value: @value),
        *@errors.map { |error| tag.p(error) }
      ].compact)
    end
  end
end
```

This minimal component renders a label, an input, and validation messages. You
can replace it with a component from your application's design system.

### 2. Define an adapter

Add `app/models/forms/text_field_adapter.rb`:

```ruby
module Forms
  class TextFieldAdapter
    def self.build(field:, options:)
      TextFieldComponent.new(
        name: field.name,
        id: field.id,
        value: field.value,
        label: field.label,
        errors: field.errors,
        **options
      )
    end
  end
end
```

Adapters can live in any Rails autoload directory. This example uses
`app/models/forms` so Rails can resolve `Forms::TextFieldAdapter` without extra
configuration.

### 3. Register the helper

Add `app/helpers/application_form_builder.rb`:

```ruby
class ApplicationFormBuilder < Formsmith::Builder
  register :text_field, adapter: "Forms::TextFieldAdapter"
end
```

### 4. Use the builder

```erb
<%= form_with model: @invoice, builder: ApplicationFormBuilder do |form| %>
  <%= form.text_field :reference %>
  <%= form.submit %>
<% end %>
```

The registered `text_field` renders your component. The unregistered `submit`
uses Rails' built-in helper.

## Usage

### Component options

Pass options alongside the attribute:

```erb
<%= form.text_field :reference, placeholder: "INV-001", class: "invoice-reference" %>
```

Options go to your adapter, which decides how to pass them to the component.
You can also override the generated binding information:

```erb
<%= form.text_field :reference, label: "Invoice number", value: nil %>
```

`name`, `id`, `value`, `errors`, and `label` are binding options. Formsmith moves
them into `field` and removes them from the adapter's `options` hash. Explicit
`nil` and `false` values are preserved rather than replaced with model values.

### Defaults and nested forms

Use `defaults:` to share options within a form:

```erb
<%= form_with model: @invoice,
              builder: ApplicationFormBuilder,
              defaults: { class: "form-input", data: { controller: "field" } } do |form| %>
  <%= form.text_field :reference %>
  <%= form.text_field :reference, class: "form-input prominent" %>
<% end %>
```

Options on an individual field override defaults. The merge is shallow: passing
`data: { action: "change->field#update" }` replaces the default `data` hash.
Defaults apply to registered helpers only.

Nested `fields_for` builders inherit these defaults. Pass `defaults:` to
`fields_for` to replace them for that nested form, or `defaults: {}` to clear
them. Rails continues to generate nested field names and IDs.

## Writing adapters

An adapter implements `build(field:, options:)` and returns a ViewComponent
instance. Formsmith renders the instance and forwards any block from the form
helper to ViewComponent's render call.

Register adapters by constant name to support Rails reloading:

```ruby
register :text_field, adapter: "Forms::TextFieldAdapter"
```

String and symbol names are resolved each time a field is rendered. You can
also pass an adapter object that responds to `build`.

Builder subclasses inherit registrations independently. To replace an existing
registration, pass `replace: true`:

```ruby
register :text_field, adapter: "Forms::CompactTextFieldAdapter", replace: true
```

### Field reference

The adapter receives a frozen `Formsmith::Field`:

| Attribute | Value |
| --- | --- |
| `object` | The form's bound object. |
| `attribute` | The field's attribute name as a symbol. |
| `name` | Rails-generated input name, including nesting and `multiple: true`. |
| `id` | Rails-generated input ID, including the form namespace. |
| `value` | Explicit override, or the model's value before type casting when available. |
| `label` | Explicit override, or the model's human-readable attribute name. |
| `errors` | An array of full validation messages for the attribute. |
| `value_supplied?` | Whether `value:` was supplied through defaults or field options, including `nil` or `false`. |

The errors array is also frozen. Password and file fields receive `nil` as their
value unless `value:` is explicitly supplied. With no bound object, the default
value is `nil`, errors are empty, and the label is the humanized attribute name.

## Rails compatibility and helper differences

Registered helpers accept `attribute, options = {}, &block`. Their options are
interpreted by your adapter and component; registering a helper does not
reproduce all of Rails' helper-specific rendering behavior.

For example, after registering a `select` adapter, pass choices as a component
option:

```erb
<%= form.select :country, options: ["AU", "NZ"] %>
```

Your adapter must handle that `options:` key. Rails' positional form,
`form.select :country, ["AU", "NZ"]`, is not supported for registered helpers.

Registering `file_field` still marks the form as multipart. Structural and
reserved helpers cannot be registered: `fields_for`, `fields`, `model_name`,
`object`, `object_name`, `options`, `multipart?`, `id`, `label`, `hidden_field`,
`button`, and `submit`.

## Development

After cloning the repository, install dependencies and run the specs:

```sh
bundle install
bundle exec rspec
```

To run against a specific Rails version, use its compatibility Gemfile:

```sh
BUNDLE_GEMFILE=gemfiles/rails_7_2.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/rails_7_2.gemfile bundle exec rspec
```

See the [changelog](CHANGELOG.md) for release history.

## Contributing

[Bug reports](https://github.com/NicolasJJensen/rails_formsmith/issues) and
[pull requests](https://github.com/NicolasJJensen/rails_formsmith/pulls) are welcome.

## License

Rails Formsmith is available under the [MIT License](LICENSE.txt).
