import { context, it, expect } from 'frontend/tests/helpers/jasmine';
import Button from '../../utils/button';

context('Button', function() {
  context("actions", function() {
    it("should set default action attributes", function() {
      var button = Button.create();
      expect(button.get('buttonAction')).toEqual('talk');
      expect(button.get('talkAction')).toEqual(true);
      expect(button.get('folderAction')).toEqual(false);
    });
    it("should keep boolean action attributes in sync based on load_board with action value", function() {
      var button = Button.create({load_board: {}});
      expect(button.get('buttonAction')).toEqual('folder');
      expect(button.get('talkAction')).toEqual(false);
      expect(button.get('folderAction')).toEqual(true);
      button.set('load_board', null);
      expect(button.get('buttonAction')).toEqual('talk');
      expect(button.get('talkAction')).toEqual(true);
      expect(button.get('folderAction')).toEqual(false);
    });
  });
  
  it("should run this test once", function() {
    expect(1).toEqual(1);
  });

  context("raw", function() {
    it("should return a plain object", function() {
      var button = Button.create();
      expect(button.raw()).toEqual({});
      button.setProperties({
        label: "hat",
        background_color: "#fff"
      });
      expect(button.raw()).toEqual({label: 'hat', background_color: '#fff'});
    });
    it("should only pull defined attributes", function() {
      var button = Button.create({
        label: "hat",
        background_color: "#fff",
        chicken: true,
        talkAction: 'ok'
      });
      expect(button.raw()).toEqual({label: 'hat', background_color: '#fff'});
    });
    
  });
  it("should run this test once too", function() {
    expect(1).toEqual(1);
  });
});
