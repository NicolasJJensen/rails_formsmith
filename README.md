# rails_formsmith

`Formsmith::Builder` maps selected Rails form helpers to explicit adapters.
It does not install itself as an application's default form builder.

Requires Ruby 3.2+, Rails 7.1 through 8.x, and ViewComponent 4.x. ViewComponent 4
sets both floors: it needs Ruby >= 3.2 and ActiveSupport >= 7.1. The suite runs
green on Rails 7.1, 7.2, 8.0, and 8.1.

## Installation

Add the gem to your Gemfile:

```ruby
gem "rails_formsmith"
```

Then run `bundle install`.

## Usage

```ruby
class ApplicationFormBuilder < Formsmith::Builder
  register :text_field, adapter: "Forms::TextFieldAdapter"
end

class Forms::TextFieldAdapter
  def self.build(field:, options:)
    TextFieldComponent.new(name: field.name, id: field.id, value: field.value,
      errors: field.errors, label: field.label, **options)
  end
end
```

Use the builder on a form:

```erb
<%= form_with model: @invoice, builder: ApplicationFormBuilder do |form| %>
  <%= form.text_field :reference %>
<% end %>
```

Adapters must respond to `build(field:, options:)` and return a renderable
ViewComponent. `field` exposes `object`, `attribute`, `name`, `id`, `value`,
`errors`, and `label`. `value_supplied?` distinguishes an explicit `value:`
override from a bound model value. String adapters are constantized when rendering, so Rails
reloads do not leave a builder holding an old class object.

`name`, `id`, `value`, `errors`, and `label` are binding options. They are
normalized into `field` and removed from the adapter's `options`, so adapters
can safely use `name: field.name, **options` without duplicate keywords.

Registered methods have the signature `attribute, options = {}, &block`.
`select :country, options: [...]` therefore sends the choices as component
options. Rails' positional select signature is intentionally not supported.
Unregistered helpers retain normal Rails behavior. `fields_for` is structural
and cannot be registered. Pass `defaults:` to a builder or form to provide scoped
component options. Nested builders inherit them unless overridden.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/NicolasJJensen/rails_formsmith.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
