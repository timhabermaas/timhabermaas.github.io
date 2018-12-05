TODO:

* For context dependent parsing you could show something like `version: 3` which changes the way the rest of the object is understood.
---
title: "Haskell -> Ruby: Parser Combinator"
---

_In this blog post I go through the process of implementing a parser combinator in Ruby. I will use Haskell's [parsec](https://hackage.haskell.org/package/parsec) library and the original [paper](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/parsec-paper-letter.pdf) as basis for the implementation, but will not follow them by the letter since enhancements like good error reporting and streaming only distract from the core idea of parser combinators._

##What is a parser?

According to [Wikipedia](https://en.wikipedia.org/wiki/Parsing#Computer_languages) a parser is

> a software component that takes input data (frequently text) and builds a data structure – often some kind of parse tree, abstract syntax tree or other hierarchical structure

So, roughly speaking a parser is a function from `String` to any object. Written using Haskell's syntax[^type-syntax]:

```haskell
parse :: String -> a
```

As an example the following function converts the strings `"true"` and `"false"` to their respective boolean values:

```ruby
def parse_boolean(text)
  if text.start_with? "true"
    true
  elsif text.start_with? "false"
    false
  end
end

parse_boolean("false") # => false
parse_boolean("true")  # => true
```

So `parse_boolean :: String -> Boolean` is a parser.

## The 'combinator' part

The basic idea behind parser combinators is to assemble small and simple parsers into large and more complex ones. For example we can try to parse `"truefalse"` into the array `[true, false]` while reusing the existing definition of `parse_boolean`:

```ruby
def parse_two_booleans(text)
  first = parse_boolean(text)
  second = if first
    parse_boolean(text[4..-1]) # Magic numbers, yay! \o/
  else
    parse_boolean(text[5..-1])
  end
  [first, second]
end
```

As you can see we need knowledge of the implementation of `parse_boolean` and if we ever decide to represent `true` by `"yes"` our code will break. This is not ideal. So, lets look at the actual (simplified) definition of parser combinators in Haskell:

```haskell
type Parser a = String -> Maybe (a, String)
```

There are two differences to our naive implementation: **a)** A parser can fail (represented by `Maybe` [^maybe]) and **b)** in case a parse succeeds the parser consumes its input and returns the remaining string. This is what enables us to compose parsers in a nicer way.

### Representing failure

Since there's no `Maybe` type in Ruby [^implement-maybe] we're left with returning `nil` or raising an exception if a parser fails. Returning `nil` would be a terrible choice since we wouldn't be able to tell a parser returning `nil` (e.g. when parsing JSON's `null`) and a failed parse apart—`Hash#[]` and `Array#[]` suffer from the same problem. Therefore let's raise a `ParseError` if we can't parse a string successfully.

### Updated implementation

When taking _failures_ and _consuming input_ into account `parse_boolean` now looks like this:

```ruby
def parse_boolean(text)
  if text.start_with? "true"
    [true, text[4..-1]]
  elsif text.start_with? "false"
    [false, text[5..-1]]
  else
    raise ParseError.new("'#{text}' starts with neither 'true' nor 'false'")
  end
end

parse_boolean("true rest")  # => [true, " rest"]
parse_boolean("false rest") # => [false, " rest"]
parse_boolean("foo rest")   # => ParseError: 'foo rest' starts with neither 'true' nor 'false'
```

By returning the remaining string composing became much nicer:

```ruby
def parse_two_booleans(text)
  first, rest = parse_boolean(text)
  second, rest = parse_boolean(rest)
  [[first, second], rest]
end

parse_two_booleans("truefalsetrue") # => [[true, false], "true"]
```

## Basic building blocks

There's still quite a lot going on in `parse_boolean`: At the top-level there's the choice between `"true"` and `"false"` and each branch consumes several characters at once. Can we split `parse_boolean` into smaller parsers? And if so what is the smallest set of parsers we need?

It turns out we only need to define the parser `satisfy :: (Char -> Bool) -> Parser Char` and can create every other parser by extending/combining `satisfy`. `satisfy` takes a property (`Char -> Bool`) and consumes exactly one character, checking whether the property holds for that character.

The following code provides one possible implementation of `satisfy`. I've also created a new class `Parser` serving as a counterpart of Haskell's `newtype`, because we need to add custom methods to a parser later on. `Parser` currently just wraps a lambda.


```ruby
class Parser
  def initialize(&block)
    @p = block
  end

  def parse(text)
    @p.call text
  end
end

def satisfy
  Parser.new do |text|
    if yield text[0]
      [text[0], text[1..-1]]
    else
      raise ParseError.new("'#{text[0]}' doesn't satisfy property")
    end
  end
end

satisfy { |t| t == "a" }.parse("a") # => ["a", ""]
satisfy { |t| t == "a" }.parse("b") # => ParseError: 'b' doesn't satisfy property
```


While theoretically `satisfy` and higher level combinators are sufficient to express any parser, I also define `string` because implementing it in terms of `satisfy` would require some combinators I'd like to introduce with the help of `string` (otherwise leading to a classic chicken-egg-problem):

```ruby
def string(s)
  Parser.new do |text|
    if text.start_with? s
      [s, text[s.size..-1]]
    else
      raise ParseError.new("couldn't match '#{s}'")
    end
  end
end
```

With `satisfy` defined we can now create a few convenient parsers:

```ruby
def char(c)
  satisfy { |token| token == c }
end

def any_char
  satisfy { |_| true }
end

def one_of(list_or_range)
  satisfy { |token| list_or_range.include? token }
end

digit  = one_of (0..9).map(&:to_s)
letter = one_of(("a".."z").to_a + ("A".."Z").to_a)
space  = char " "
```


## Combinators

Combinators can also be thought of as higher-level parsers, meaning they take a parser as input and create a new one. So, in some sense they can be compared to meta programming.

### Apply a parser multiple times

TODO: Explain the code better.
In order to parse a number in TOML we need to apply `digit` to our input until there are no digits left.

```ruby
def many1(p)
  Parser.new do |text|
    result, rest = p.parse(text)
    tokens = [result]
    loop do
      result, rest = p.parse(rest)
      tokens << result
    end
    [tokens, rest]
  end
end

digits = many1(digit)
digits.parse("123 rest") # => [["1", "2", "3"], " rest"]
```

However `digits` returns `["1", "2", "3"]` which isn't very nice to work with. We'd like to get the integer `123` back. So, it would be nice to change the return value of a parser without changing the parser itself. This leads us to the next combinator:

### Changing results (aka [Functor](https://hackage.haskell.org/package/base-4.10.0.0/docs/Data-Functor.html#t:Functor))

In Ruby we're already used to calling `map` in order to apply a function to all elements of an array. If we think of a parser as a black box returning either one element (`[x]`, success) or zero elements (`[]`, parse error), calling `map` feels like a natural way to change the parser's result. In fact, Haskell already has a concept for objects which can be mapped over called a [Functor](https://wiki.haskell.org/Functor). Due to historical reasons `map` is called `fmap :: (a -> b) -> f a -> f b` in Haskell, though. While the name `map` would be nicer, I'll go with `fmap` as well in order to avoid confusion with `Array#[]`. Assuming we've already implemented `fmap` we should be able to write the following code to get integer values when parsing digits:

```ruby
integer = digits.fmap { |list| list.join.to_i }
# Or equivalent:
# integer = digits.fmap(&:join).fmap(&:to_i)
integer.parse("123 rest") # => [123, " rest"]
```

The implementation of `fmap` is pretty straightforward. We build a new parser which calls the original parser (`self`) and `yield`s the result to the block. The remaining string remains unchanged:

```ruby
class Parser
  def fmap
    Parser.new do |text|
      result, rest = self.parse(text)
      [yield result, rest]
    end
  end
end
```

With `string` and `fmap` in place we can also simplify our boolean parsers:

```ruby
true_parser = string("true").fmap { |_| true }
false_parser = string("false").fmap { |_| false }
```

We notice that we don't even need `fmap`'s block parameter. It would be nice to have a more concise syntax for these cases were the block is just a constant function. So, lets steal from Haskell again. In the [`Data.Functor`](https://hackage.haskell.org/package/base-4.10.0.0/docs/Data-Functor.html) module there are several functions defined in terms of `fmap`. Two of them are [`$> :: f a -> b -> f b`](https://hackage.haskell.org/package/base-4.10.0.0/docs/Data-Functor.html#v:-36--62-) and [`<$ :: b -> f a -> f b`](https://hackage.haskell.org/package/base-4.10.0.0/docs/Data-Functor.html#v:-60--36-). Both of them take a functor and some value and return a new functor with the _return value_ replaced. Unfortunately we can't copy the functions verbatim because Ruby doesn't allow defining arbitrary operators. We could overload `>` though:

```ruby
class Parser
  def >(constant)
    self.fmap { |_| constant }
  end
end
```

```ruby
true_parser = string("true") > true
false_parser = string("false") > false
```

That's nicer and we're very close to rewriting `parse_boolean` in terms of `true_parser` and `false_parser`. However, we still need a way to express branching (like we did with `if/elsif` earlier). This leads us to:

### Choice (aka [Alternative](https://hackage.haskell.org/package/base-4.10.0.0/docs/Control-Applicative.html#t:Alternative))


Haskell: `<|> :: f a -> f a -> f a`

* same types, but restriction doesn't exist in Ruby? Does this break any laws?
* What about the identity? Do we need it?

```ruby
boolean_parser = true_parser | false_parser
```


```ruby
class Parser
  def |(other)
    Parser.new do |text|
      begin
        self.parse(text)
      rescue ParseError
        other.parse(text)
      end
    end
  end
end
```



### Lifting a function (aka [Applicative Functor]())


### Sequencing

### Backtracking

Introduce `try`

Date vs. Integer (1992-12-32 vs 21

## Final parser

```ruby
alphaNum = letter | digit
key = many1(alphaNum).fmap(&:join)
string = char('"') > many(not(char('"'))) < char('"')
year = digit.count(4).fmap(&:join).fmap(&:to_i)
month = digit.count(2).fmap(&:join).fmap(&:to_i)
day = digit.count(2).fmap(&:join).fmap(&:to_i)
date = Parser.lift(year, month, day) { |y, m, d| Date.new(y, m, d) }
boolean = (string("true") > true) | (string("false") > false)
integer = many1(digit).fmap(&:join).to_i
value = date | integer | string | boolean
line = Parser.lift(key, string(" = "), value) { |k, _, v| {k => v} }
# TODO: use line.sepEndBy(newline)
lines = many(line < newline).fmap { |lines| lines.reduce({}) { |acc, h| acc.merge(h) } }
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
[^maybe]: See the paper [When Maybe is not good enough](http://www.cs.tufts.edu/~nr/cs257/archive/mike-spivey/maybe-not-enough.pdf) for when you would need a more sophisticated aproach than a simple `Maybe`.
[^implement-maybe]: Of course we could port `Maybe` to Ruby and that's probably what I'd do in a serious implementation, but I wanted to keep the focus on parser combinators and not introduce another concept.
