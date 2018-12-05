class Some
  def initialize(v)
    @v = v
  end

  def fmap
    Some.new(yield @v)
  end
end

class None
  def fmap
    self
  end
end

class Prism
  def initialize(forward, backward)
    @forward, @backward = forward, backward
  end
end

module J
  def self.object
  end

  def self.prop(key, valueJ)
    Prism.new(-> (h) { h.has?(key) ? { key =>
  end
end

J.liftA(partialIso)
