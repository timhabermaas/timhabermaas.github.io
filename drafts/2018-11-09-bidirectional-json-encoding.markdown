---
title: "Bidirectional JSON parsing in Ruby"
---

In this blog post I want

## Motivation

Usually
`to_json`/`as_json` and some ad-hoc parsing like `json[:date] = Date.parse(json[:date])`

```ruby
J.object(
  J.prop('foo', J.int),
  J.prop('bar', J.string)
)
```

```ruby
J.array(J.string)
```

* Prisms for the rescue
* The problem with choice

## The problem with choice

Often the conversion of values is not as straightforward as parsing a string as
a date.
straightforward as parsing a string as a date

Example: Infinity <-> "31.12.2999"

```ruby
```

