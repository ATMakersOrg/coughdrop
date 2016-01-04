describe('User', function() {
  beforeEach(function() {
    Ember.testing = true;
    CoughDrop.reset();
  });
  
  describe("avatar_url_with_fallback", function() {
    it("should key off avatar_url if defined", function() {
      var u = CoughDrop.store.createRecord('user', {avatar_url: "http://pic.example.com"});
      expect(u.get('avatar_url_with_fallback')).toEqual("http://pic.example.com");
      
      // TODO: this doesn't belong here
      var router = CoughDrop.Router.create();
      router.router.recognizer.recognize("/bacon");
    });
    it("should automatically check for locally-stored avatar data-uri on load", function() {
      var user = CoughDrop.store.createRecord('user');
      user.didLoad();
      expect(user.get('checked_for_data_url')).toEqual(true);
    });
  });
  
  describe("registration", function() {
    it("should clear password on successful registration");
  });
});
