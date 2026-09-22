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

For field registrations, `name`, `id`, `value`, `errors`, and `label` are binding
options. Formsmith applies their overrides when constructing `field`, then
removes those keys from the adapter's `options` hash. For example:

```ruby
form.text_field :reference, label: "Invoice number", value: nil, class: "input"

# Inside the adapter:
field.label # => "Invoice number"
field.value # => nil
options     # => { class: "input" }
```

This gives binding information one authoritative location. An adapter can map
`field.label` to a component's `caption:` argument, or format `field.value`,
without `**options` forwarding the original key and overriding that decision.

Omitting `value:` uses the model value when available. Passing `value: nil`
explicitly clears it; `value: false` also remains false. `errors: nil` becomes
an empty array. The component decides how to render these values.

A field name does not have to be an attribute on the model:

```erb
<%= form.text_field :image_owner %>
<%= form.text_field :image_owner, value: "Alice" %>
```

Without an `image_owner` reader, the first call receives `field.value == nil`.
The second receives `"Alice"`. Both still get generated names, IDs, labels, and
any validation errors for that field name. Virtual attributes with readers work
like other model values.

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

Defaults apply to registered helpers only. By default, merging is shallow:
field options replace defaults with the same key. Passing
`data: { action: "change->field#update" }` therefore replaces the default `data`
hash entirely.

Choose a default policy on your builder:

```ruby
class ApplicationFormBuilder < Formsmith::Builder
  defaults_merge :deep

  register :text_field, adapter: "Forms::TextFieldAdapter"
end
```

Or override the policy for a form:

```erb
<%= form_with model: @invoice,
              builder: ApplicationFormBuilder,
              defaults_merge: :deep,
              defaults: { data: { controller: "field" } } do |form| %>
  <%= form.text_field :reference, data: { action: "change->field#update" } %>
<% end %>
```

Here the adapter receives both `data[:controller]` and `data[:action]`.

| Policy | Behavior |
| --- | --- |
| `:shallow` | Replace each top-level default with the supplied option. The fallback policy. |
| `:deep` | Merge nested hashes recursively. Arrays, strings, and other values replace defaults. |
| `:adapter` | Call the adapter's `merge_options(defaults:, options:)` method. |

Both built-in policies preserve explicit `nil` and `false` overrides. Neither
concatenates CSS classes or controller names.

A registration can pin a policy with `merge:`:

```ruby
register :text_field, adapter: "Forms::TextFieldAdapter", merge: :adapter
```

Precedence is **registration `merge:` → form `defaults_merge:` → builder
`defaults_merge` → `:shallow`**. All three configuration levels accept the same
policies. Builder subclasses inherit the builder policy and can override it.

Nested `fields_for` builders inherit the form's defaults and effective merge
policy. Pass `defaults:` to replace the nested defaults, `defaults: {}` to clear
them, or `defaults_merge:` to override the nested policy. Registration policies
still take precedence. Rails continues to generate nested field names and IDs.

### Adapter-controlled merging

With `merge: :adapter`, Formsmith passes independent copies of the original
defaults and caller options to `merge_options`. Nothing has been merged or
removed yet. The method must return a Hash; missing methods or invalid results
raise `ArgumentError`.

For example, this adapter combines string classes and `data-controller` tokens
while deep-merging other options:

```ruby
module Forms
  class TextFieldAdapter
    def self.merge_options(defaults:, options:)
      merged = defaults.deep_merge(options)

      if options.key?(:class)
        merged[:class] = combine_tokens(defaults[:class], options[:class])
      end

      if options[:data].is_a?(Hash) && options[:data].key?(:controller)
        merged[:data][:controller] = combine_tokens(
          defaults.dig(:data, :controller), options[:data][:controller]
        )
      end

      merged
    end

    def self.combine_tokens(default, override)
      return nil if override.nil? || override == false

      [default, override].compact.flat_map { |value| value.split }.uniq.join(" ")
    end

    private_class_method :combine_tokens

    # Keep the build(field:, options:) implementation from the quick start.
  end
end
```

This example expects symbol keys and string token lists (or `nil`/`false` to
clear a list). `class: "input"` plus `class: "prominent"` becomes
`class: "input prominent"`. It deduplicates identical tokens, but does not resolve
conflicting CSS utilities. Other component APIs can implement their own policy.

After merging, Formsmith resolves the field binding and removes its binding
keys from component options. For raw registrations, it passes the entire merged
hash to the adapter. Adapter mutations do not change the original defaults or
caller option hashes.

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

### Helpers with raw arguments

The default registration mode is `arguments: :field`: the first argument is a
field name, whether or not the model has a corresponding reader. For buttons,
actions, or components with multiple positional arguments, use the same
`register` method with `arguments: :raw`:

```ruby
class ApplicationFormBuilder < Formsmith::Builder
  register :text_field, adapter: "Forms::TextFieldAdapter"
  register :submit, adapter: "Forms::SubmitAdapter", arguments: :raw
end
```

A raw adapter receives `arguments:` instead of `field:`:

```ruby
module Forms
  class SubmitAdapter
    def self.build(arguments:, options:)
      SubmitComponent.new(text: arguments.fetch(0, "Save"), **options)
    end
  end
end
```

For example, `app/components/submit_component.rb` could contain:

```ruby
class SubmitComponent < ViewComponent::Base
  def initialize(text:, **options)
    @text, @options = text, options
  end

  def call
    tag.button(content.presence || @text, **@options, type: "submit")
  end
end
```

```erb
<%= form.submit "Save invoice", class: "primary", name: "commit", value: "save" %>
```

The adapter receives `arguments: ["Save invoice"]` and all merged options,
including `name` and `value`. No Field is constructed and no binding keys are
removed. A call without positional arguments receives `arguments: []`. Blocks
are forwarded to the returned component for rendering.

Raw helpers accept any number of positional arguments. A trailing hash is
treated as options; keyword options override duplicate keys in that hash. This
convention also applies to field registrations, which require exactly one field
name after extracting options.

A raw adapter owns the argument semantics. The example chooses `"Save"` as its
default text; Formsmith does not supply Rails' model-aware create/update labels.
Likewise, registering a composite helper does not automatically bind each of
its positional arguments to model attributes.

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

Field registrations accept a field name and an options hash; raw registrations
forward positional arguments to the adapter. Their options are
interpreted by your adapter and component; registering a helper does not
reproduce all of Rails' helper-specific rendering behavior.

For example, after registering a `select` adapter, pass choices as a component
option:

```erb
<%= form.select :country, options: ["AU", "NZ"] %>
```

Your adapter must handle that `options:` key. Rails' positional form,
`form.select :country, ["AU", "NZ"]`, is not supported for registered helpers.

Registering `file_field` still marks the form as multipart. Rendering helpers
such as `label`, `hidden_field`, `button`, and `submit` may be registered. Use
raw mode when their arguments do not follow the field-name convention. Your
adapter and component must implement any required helper-specific behavior;
for example, a registered hidden field may also be used for Rails-generated
nested record identifiers.

Builder infrastructure remains reserved: `fields_for`, `fields`, `model_name`,
`object`, `object_name`, `options`, `multipart?`, `multipart=`, `id`, `field_name`,
`field_id`, `component_defaults`, and `defaults_merge`. Replacing these would
interfere with scope creation, binding generation, or builder state.

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
