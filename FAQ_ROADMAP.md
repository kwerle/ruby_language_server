# Why docker?

Docker guarantees me a target environment.  I don't have to wonder which version of ruby you have installed or if you can build all the gems.  I may also scale this thing to multiple processes and a database and a cache server.

One requirement: docker.

# Why not [language_server-ruby](https://github.com/mtsmfm/language_server-ruby)

My goals are not as high.  I just want this stuff working now.  I hope some day there will be merging.

# A little light on tests?

Oh yeah.  Tests are mostly for when you know where you're going.  I'm doing a whole lot of this by the seat of my pants.  OMG, please write tests.

# Next?

* Guess a symbol's class.
  * `def some_method(parent)` should guess that parent is a Parent.
* Be smarter about context and completions
* `class << self` is busted.  Fix it.
* Fix the outline.  Seriously - why isn't it working as expected?
* Symbol pairs.  If I have typed 'foo.bar' a thousand times in my project, the next time I type 'foo.' the IDE had damn well ought to show me 'bar' as a completion option.
* It makes me very sad that I could not get this working using sockets.  Tried and tried and failed.

# Then?

* Pay special attention to the project's Gemfile.  Install all the gems (we can).  Integrate with gem server?
  * Full scan of installed gems?
* Integrate class based scope logic.  If I'm in Foo < Bar then I should see Bar's methods at just slightly lower priority than Foo's.
