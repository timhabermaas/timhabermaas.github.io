# TODO: Use input as block argument consistently.
Point = Struct.new(:x, :y)
RGB = Struct.new(:red, :green, :blue)
Circle = Struct.new(:center, :radius, :color, :visible)
Rectangle = Struct.new(:top_left, :bottom_right, :color, :visible)

class Err
  def initialize(error)
    @error = error
  end

  def to_s
    "Err(#{@error})"
  end

  def then
    self
  end

  def unwrap
    raise "can't unwrap Err"
  end

  def error?
    true
  end
end

class Ok
  def initialize(value)
    @value = value
  end

  def to_s
    "Ok(#{@value})"
  end

  def then
    yield @value
  end

  def unwrap
    @value
  end

  def error?
    false
  end
end

class Decoder
  def initialize(&block)
    @f = block
  end

  def run(value)
    @f.call(value)
  end

  def fmap
    Decoder.new do |input|
      result = self.run(input)
      if result.error?
        result
      else
        Ok.new(yield result.unwrap)
      end
    end
  end

  def then
    Decoder.new do |input|
      result = self.run(input)
      if result.error?
        result
      else
        (yield result.unwrap).run(input)
      end
    end
  end

  def |(decoder)
    Decoder.new do |input|
      result = self.run(input)
      if result.error?
        decoder.run(input)
      else
        result
      end
    end
  end

  def >(value)
    fmap { |_| value }
  end

  def self.integer
    self.new do |s|
      begin
        Ok.new(Integer(s))
      rescue TypeError, ArgumentError
        Err.new("'#{s}' is not an integer")
      end
    end
  end

  def self.id
    self.new do |s|
      Ok.new(s)
    end
  end

  def self.succeed(v)
    self.new do |_|
      Ok.new(v)
    end
  end

  def self.fail(e)
    self.new do |_|
      Err.new(e)
    end
  end

  def self.match(constant)
    self.new do |s|
      s == constant ? Ok.new(s) : Err.new("'#{s}' doesn't match '#{constant}'")
    end
  end

  def self.from_key(key, decoder)
    self.new do |hash|
      return Err.new("'#{hash}' is not of type Hash") unless hash.is_a?(Hash)
      return Err.new("'#{hash}' doesn't contain key '#{key}'") unless hash.has_key?(key)

      decoder.run(hash.fetch(key))
    end
  end

  def self.mapN(*decoders, &block)
    raise "decoder count must match argument count of provided block" unless decoders.size == block.arity

    self.new do |input|
      results = decoders.map do |c|
        c.run(input)
      end

      first_error = results.find(&:error?)
      if first_error
        first_error
      else
        Ok.new(block.call(*results.map(&:unwrap)))
      end
    end
  end

  def self.map2(decoder1, decoder2)
    self.new do |x|
      decoder1.run(x).then do |result1|
        decoder2.run(x).then do |result2|
          Ok.new(yield result1, result2)
        end
      end

      # if result1.error?
      #   return result1
      # else
      #   result2 = decoder2.run(x)
      #   if result2.error?
      #     return result2
      #   else
      #     Ok.new(yield result1.unwrap, result2.unwrap)
      #   end
      # end
    end
  end
end

point =
  Decoder.map2(
    Decoder.from_key("x", Decoder.integer),
    Decoder.from_key("y", Decoder.integer)
  ) do |x, y|
    Point.new(x, y)
  end

visibility = (Decoder.match("visible") > true) |
             (Decoder.match("invisible") > false)

color = Decoder.id.fmap(&:upcase)

circle =
  Decoder.mapN(
    Decoder.from_key("center", point),
    Decoder.from_key("radius", Decoder.integer),
    Decoder.from_key("color", color),
    Decoder.from_key("status", visibility)
  ) do |center, radius, color, visibility|
    Circle.new(center, radius, color, visibility)
  end

rectangle =
  Decoder.mapN(
    Decoder.from_key("topLeft", point),
    Decoder.from_key("width", Decoder.integer),
    Decoder.from_key("height", Decoder.integer),
    Decoder.from_key("color", color),
    Decoder.from_key("status", visibility)
  ) do |top_left, width, height, color, visible|
    Rectangle.new(top_left, Point.new(top_left.x + width, top_left.y + height), color, visible)
  end

geometry = Decoder.from_key("type", Decoder.id).then do |type|
  if type == "circle"
    circle
  elsif type == "rectangle"
    rectangle
  else
    Decoder.fail("type must be either 'circle' or 'rectangle'")
  end
end

p1 = {
  "type" => "circle",
  "center" => {
    "x" => "10",
    "y" => "12"
  },
  "radius" => "4",
  "color" => "red",
  "status" => "visible2"
}

p2 = {
  "type" => "rectangle",
  "topLeft" => {
    "x" => "0",
    "y" => "3"
  },
  "width" => "4",
  "height" => "5",
  "color" => "blue",
  "status" => "invisible"
}

p geometry.run(p1)
p geometry.run(p2)
