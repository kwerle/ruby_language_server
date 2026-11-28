# Next?

* Getting a definition just looks at the tags - but tags do not include parameters passed in a method - which seems like it should.  We are functional, right?
* Be smarter about context and completions
* Symbol pairs.  If I have typed 'foo.bar' a thousand times in my project, the next time I type 'foo.' the IDE had damn well ought to show me 'bar' as a completion option.
* Sockets now work: set `LSP_PORT` and the server takes one LSP connection over TCP. It's used for debugging (see "Debugging the server" in the [README](README.md)); the editor clients still use stdio.

# Then?

* Gems from Gemfile.lock are indexed (GemIndex) but downloaded again every start. Cache them, or mount the host's installed gems, which would also let go-to-definition open them.
* ActiveSupport's core extensions (blank?, present?, 3.days) alongside the Ruby core classes. They're plain Ruby, so the existing parser can read them.
* Go-to-definition for Ruby core methods, through a virtual document for the .rbs file.
* Know what type a local variable holds, so `name.up` completes String methods.
* Integrate class based scope logic.  If I'm in Foo < Bar then I should see Bar's methods at just slightly lower priority than Foo's.
