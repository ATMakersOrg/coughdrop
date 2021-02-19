import modal from '../../utils/modal';
import i18n from '../../utils/i18n';
import utterance from '../../utils/utterance';
import RSVP from 'rsvp';
import stashes from '../../utils/_stashes';
import { computed } from '@ember/object';

export default modal.ModalController.extend({
  opening: function() {
    this.set('lang', stashes.get('display_lang'));
  },
  locales: computed(function() {
    var list = i18n.locales_translated || ['en'];
    return list.map(function(loc) {
      var auto_translated = loc.match(/\*/);
      var loc = loc.replace(/\*/, '');
      var name = i18n.locales_localized[loc] || i18n.locales[loc] || loc;
      if(auto_translated) {
        name = name + " (auto-translated)";
      }
      return {
        name: name, 
        id: loc
      };  
    });
  }),
  actions: {
    update: function() {
      stashes.persist('display_lang', this.get('lang'));
      location.reload();
    },
  }
});
