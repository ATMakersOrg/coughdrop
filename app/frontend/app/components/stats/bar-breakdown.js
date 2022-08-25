import Component from '@ember/component';
import { htmlSafe } from '@ember/string';
import { computed } from '@ember/object';
import CoughDrop from '../../app';
import image from '../../models/image';

var color_index = 0;
var colors = [
  ['#444', '#999'],
  ['#63130e', '#962d26'],
  ['#0e6318', '#329c3e'],
  ['#12546b', '#32809c'],
  ['#4b4d0a', '#868a24'],
  ['#3b0d54', '#66248a'],
]
export default Component.extend({
  rows: computed('hash', 'order', function() {
    var list = [];
    var hash = this.get('hash');
    console.log("HASH", hash);
    var max = 0;
    var statuses = {};
    if(this.get('order') == 'status') {
      CoughDrop.user_statuses.forEach(function(s, idx) {
        statuses[s.id] = [idx, s];
      });
    }
    for(var key in hash) {
      if(hash[key]) {
        var item = {id: key, val: hash[key], score: parseInt(hash[key], 10)};
        item.index = item.score;
        item.label_style = 'padding: 5px 0; max-height: 50px; overflow: hidden;';
        if(this.get('order') == 'status') {
          item.label_style = item.label_style + 'text-align: left;';
          item.link = "status-" + item.id;
          var ref = statuses[item.id];
          if(ref) {
            item.index = 100 - ref[0];
            item.glyph = htmlSafe('glyphicon glyphicon-' + item.id);
            item.id = ref[1].label;
          }
        } else {
          item.label_style = item.label_style + 'text-align: right;';
        }
        if(this.get('order') == 'size') {
          item.index = parseInt(item.id, 10);
        }
        list.push(item);
        max = Math.max(max, item.score);
      }
    }
    list.forEach(function(item) {
      console.log(item.score, max);
      var color = colors[color_index % colors.length];
      item.style = htmlSafe('width: ' + Math.round(item.score / max * 100) + '%; border: 2px solid ' + color[0] + '; background: ' + color[1] + '; height: 40px; border-radius: 5px; color: #fff; font-size: 12px; padding-left: 3px;');
      color_index++;
    });
    return list.sortBy('index').reverse();
  }),
  actions: {
  }
});