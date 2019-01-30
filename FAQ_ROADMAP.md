# Next?

* Getting a definition just looks at the tags - but tags do not include parameters passed in a method - which seems like it should.  We are functional, right?
* Be smarter about context and completions
* Symbol pairs.  If I have typed 'foo.bar' a thousand times in my project, the next time I type 'foo.' the IDE had damn well ought to show me 'bar' as a completion option.
* It makes me very sad that I could not get this working using sockets.  Tried and tried and failed.

# Then?

* Pay special attention to the project's Gemfile.  Install all the gems (we can).  Integrate with gem server?
  * Full scan of installed gems?
  * Maybe use a database (sqlite?) to store data and do lookups?
* Integrate class based scope logic.  If I'm in Foo < Bar then I should see Bar's methods at just slightly lower priority than Foo's.
