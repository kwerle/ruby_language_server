bogus = Some::Bogus
module Foo
  class Bar
    SOME_CONSTANT = 42
    @bottom = 1

    public def baz(bing, zing)
      zang = 1
      @biz = bing
      @biz = bang
    end

    private

    def ding
    end
  end

  class Nar < Bar
    attr :top

    private

    def naz(ning)
      @niz = ning
    end
  end

  module Zar
    class << self
      def zoo(par)
        paf = par
      end
    end

    def self.zor(par)
      pax = par
    end
  end

end
