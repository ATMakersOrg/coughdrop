import Route from '@ember/routing/route';
import session from '../utils/session';

export default Route.extend({
  title: "Login",
  setupController: function(controller) {
    controller.set('login_id', "");
    controller.set('login_password', "");
    if(location.search && location.search.match(/^\?model-/)) {
      var parts = decodeURIComponent(location.search.replace(/^\?/, '')).split(/:/);
      if(parts[0] && parts[1]) {
        controller.set('login_id', parts[0].replace(/-/, '@').replace(/_/, '.'));
        controller.set('login_password', parts[1].replace(/-/, '?:#'));
        history.replaceState({}, null, "/login");
      }
    } else if(location.search && location.search.match(/^\?auth-/)) {
      var tmp_token = decodeURIComponent(location.search.replace(/^\?auth-/, ''));
      controller.set('tmp_token', tmp_token);
      // TODO: auto-check token from redirect
      history.replaceState({}, null, "/login");
    }
    if(session.get('isAuthenticated')) {
      debugger
    }
  }
});
