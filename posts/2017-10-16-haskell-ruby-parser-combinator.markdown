---
title: "Haskell -> Ruby: Parser Combinator"
---

_In this blog post I explain the process of porting Haskell's [parsec](https://hackage.haskell.org/package/parsec) library to Ruby. I will only implement a small and simplified version of parsec, though. Details such as error reporting and streaming distract from the core idea of parser combinators and will not be part of the final toy implementation._

##What is a parser?

According to [Wikipedia](https://en.wikipedia.org/wiki/Parsing#Computer_languages) a parser is

> a software component that takes input data (frequently text) and builds a data structure – often some kind of parse tree, abstract syntax tree or other hierarchical structure

So, roughly speaking a parser is a function from `String` to any object—written `parse :: String -> a` in Haskell [^type-syntax]. As an example the following function converts the strings `"true"` and `"false"` to their respective boolean values:

```ruby
def parse_boolean(text)
  case text
  when "true"
    true
  when "false"
    false
  end
end

parse_boolean("false") # => false
parse_boolean("2")     # => nil
```

`parse_boolean` doesn't handle failures particular well though.

As you can see the parser doesn't handle failures particular well.

```haskell
newtype Parser a = Parser { runParser :: String -> Maybe (a, String) }
```

```ruby
class Parser
  def initialize(&block)
    @parser = block
  end

  def parse(s)
    @parser.call s
  end
end

boolean = Parser.new do |text|
  case text
  when "true"
    true
  when "false"
    false
  end
end

boolean.parse("false") # => false
boolean.parse("2") # => nil
```

As you can see the `String -> Boolean` type signature is actually a lie: When providing neither `"true"` nor `"false"` as inputs to `parse_boolean` the function returns `nil`. Since all but the most trivial parsers can fail we need to account for failure.

There are at least four ways to represent a failed parse attempt:

* `nil`: _has the same problem as `Hash#[]`—a successful parse with return value `nil`[^nil] can't be differentiated from a failed parse_
* `[a]`: _empty array represents error case; awkward to work with, requires lots of destructuring or `.first` calls_
* `Maybe a`: _easy to work with, but requires porting `Maybe` to Ruby as well_
* raising an exception: _doesn't compose well, but keeps the implementation clean_

For the reasons stated above we'll raise a `ParseError` exception. In actual production code you might want to use `[a]` or `Maybe a` depending on the languages you want to parse[^maybe].


`Integer("30")` would be an example of a parser returning an integer. In practice `Integer` and most parsers can fail, though, so we need to account for that.

There are several ways to indicate failure:


If we restrict ourselves to text as input and extend the possible outputs to any object, a parser in Ruby can be expressed as a function from `String` to `BasicObject` (written `String -> BasicObject`[^type-syntax] in Haskell). As an example `Integer("30")` is a parser which takes a `String` and returns an `Integer`. In practice `Integer` and most parsers can fail, though, so we need to account for that. By abusing `Array` and using the empty list to describe failure we can fix this [^2]:

```ruby
def parse_int(text)
  [Integer(text)]
rescue
  []
end

parse_int("30") => [30]
parse_int("a") => []
```

Since we'll soon need a common abstraction for all parsers we wrap our function in an object with a `parse` method. This way all parsers share the same interface (`parse :: String -> BasicObject`) and we're able to extend parsers with more helper methods:

```ruby
class Parser
  def initialize(&block)
    @parser = block
  end

  def parse(s)
    @parser.call s
  end
end

int_parser = Parser.new { |text| [Integer(text)] rescue [] }
int_parser.parse("30") # => [30]
int_parser.parse("a") # => []
```

## Concrete use-case

In order to have something concrete to work with we're trying to build a parser for a subset of [TOML](https://en.wikipedia.org/wiki/TOML). Our parser will have (at least) the following restrictions:

  * no nested arrays
  * no tables
  * no floats
  * only dates, no datetimes
  * very strict whitespace parsing

Here's a valid document which we will be able to successfully parse at the end:

```toml
name = "Tom Preston-Werner"
dob = 1979-05-27
height = 182
married = true
```

`parse_toml(s)` should yield the following Ruby object:

```ruby
{
  name: "Tom Preston-Werner",
  dob: Date.new(1979, 5, 27),
  height: 182,
  married: true
}
```

## What about the 'combinator' part?

While writing single ad-hoc parsers is fine for small grammars, you probably want to have more sophisticated methods available once you start writing more complex parsers (e.g. for TOML). That's where the _combinator_ part comes into play. The idea is to combine small simple parsers into more complex ones.

### Basic building blocks

In order to combine simple parsers into more complex ones we need to define simple parsers first. The simplest parser is propably the one parsing one character:

```ruby
any_char = Parser.new { |text| [text[0]] }
```

We also need a way to check for specific characters, though. For example `=` is used as the delimiter between key/value pairs in TOML. Therefore lets define a helper function which creates a parser expecting a particular character:

```ruby
def char(c)
  Parser.new do |text|
    if text[0] == c
      [c]
    else
      []
    end
  end
end

char(":").parse(":") # => [":"]
char(":").parse("x") # => []
```

#

### Combinators

If we want to parse the ASCII arrow `"->"` we would need a way to write a parser expecting a dash followed by a greater than sign: `char("-") + char(">")`

The implementation of `+` would need to run the first parser and in case it succeeded run the second parser.
If we start implementing `+` for `Parser` we might end up with something like this:

```ruby
class Parser
  def +(other)
    Parser.new do |text|
      first_result = self.parse(text)
      next [] if first_result.empty?
      second_result = other.parse(text[1..-1])
      next [] if second_result.empty?
      [first_result.first + second_result.first]
    end
  end
end
```

This code has two problems though: _a)_ It assumes that the first parser only consumes one character and _b)_ it assumes that the results of the parsers are of type `String` and can therefore be safely combined using `String#+`. Both of these assumptions don't necessarily hold: you could create a parser which parsers several characters and returns an integer, just like `int_parser` did earlier.

While _a)_ could be solved by counting the characters returned from the first parser, it will still break when the returned values are not strings. Therefore we need a more generic solution to combine two parsers.

Lets solve _a)_ first: If we not only return the parsed values from a parser, but also the remaining string we wouldn't need to count any characters or depend on other hacks to figure out how many characters the previous parser looked at. So, we change our definitions of `any_char` and `char` accordingly:

```ruby
any_char = Parser.new { |text| [text[0], text[1..-1]] }

def char(c)
  Parser.new do |text|
    if text[0] == c
      [c, text[1..-1]]
    else
      []
    end
  end
end
```

We could now implement `+`, and feed the remaining string of the first parser to the second. However, we'd still have to hardcode the way we want to combine the two results.

```ruby
def combine(a, b)
  Parser.new do |text|
    first = a.parse(text)
    next [] if first.empty?
    first_result, remaining = first
    second = b.parse(remaining)
    next [] if second.empty?
    second_result, remaining = second
    [yield first_result, second_result, remaining]
  end
end
```

## Parsing "TOML"

[^type-syntax]: I'm using Haskell's type signature throughout this post because it is concise and, in my opinion, readable for anyone vaguely familar with static types. There's also no standard way to express type signatures in Ruby that I'm aware of.
[^2]: Returning `nil` (or any other object) is not an option, because we wouldn't be able to distinguish between a successful parse returning `nil` (e.g. it's reasonable to parse `"null"` to `nil`) and an unsuccessful one. `Hash#[]` suffers from the same issue. Using (and porting) Haskell's [`Maybe`](https://hackage.haskell.org/package/base-4.10.0.0/docs/Data-Maybe.html) data type would be another option, but using `Array` has the advantage of being already built into Ruby.
[^nil]: One possible use case would be parsing the JSON value `"null"` into `nil`.
[^maybe]: See paper [When Maybe is not good enough](http://www.cs.tufts.edu/~nr/cs257/archive/mike-spivey/maybe-not-enough.pdf).
