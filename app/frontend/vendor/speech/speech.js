// first draft of web speech synthesis polyfill
// https://dvcs.w3.org/hg/speech-api/raw-file/tip/speechapi.html#tts-section
window.originalSpeechSynthesis = window.speechSynthesis;
window.originalSpeechSynthesisUtterance = window.SpeechSynthesisUtterance;
if(!window.SpeechSynthesisUtterance) {
  if(window.speechSynthesis) {
    window.polyspeech = {};
    window.polyfillSpeechSynthesis(window.polyspeech);
  } else {
    window.polyfillSpeechSynthesis(window);
  }
}

function polyfillSpeechSynthesis(scope) {
  function PolySpeechSynthesis() {
    var speech = this;
    var utterances = [];
    var currentUtterance = null;
    function nextUtterance() {
      currentUtterance = null;
      if(utterances.length > 0) {
        if(speech.paused) {
          speech.speaking = false;
          speech.pending = true;
        } else {
          speech.speaking = true;
          var utterance = utterances.shift();
          currentUtterance = utterance;
          speech.pending = utterances.length > 0;
          utterance.bind('end', nextUtterance);
          utterance.beginSpeaking();
        }
      } else {
        speech.speaking = false;
        speech.pending = false;
      }
    }
  
    this.speaking = false;
    this.pending = false;
    this.paused = false;
    this.polyfill = true;
    this.speak = function(utterance) {
      utterances.push(utterance);
      speech.pending = true;
      if(!speech.speaking) {
        nextUtterance();
      }
    };
    this.cancel = function() {
      speech.paused = false;
      speech.speaking = false;
      speech.pending = false;
      if(currentUtterance) {
        currentUtterance.pauseSpeaking();
      }
      utterances = [];
      currentUtterance = null;
    };
    this.pause = function() {
      speech.paused = true;
      if(currentUtterance) {
        currentUtterance.pauseSpeaking();
      }
    };
    this.resume = function() {
      speech.paused = false;
      if(currentUtterance) {
        currentUtterance.resumeSpeaking();
      } else {
        nextUtterance();
      }
    };
    this.voiceList = [];
    this.getVoices = function() {
      return speech.voiceList;
    };
  };

  function PolySpeechSynthesisUtterance(text, lang, voiceURI, volume, rate, pitch) {
    var utterance = this;
    this.text = text; // text or SSML
    this.lang = lang;
    this.voiceURI = voiceURI; // optional serviceURL
    this.volume = volume;
    this.rate = rate;
    this.pitch = pitch;
    this.charIndex = null;
    this.elapsedTime = null;
    this.onstart = null;
    this.onend = null;
    this.onerror = null; // not implemented
    this.onpause = null; // not implemented
    this.onresume = null; // not implemented
    this.onmark = null; // not implemented
    this.onboundary = null; // not implemented
    this.beginSpeaking = function() {
      utterance.charIndex = undefined;
      utterance.elapsedTime = 0;
      utterance.startTime = (new Date());
      utterance.trigger('start');
      triggerActualSpeechSynthesis(utterance);
    };
    this.pauseSpeaking = function() {
      if(utterance.attachedPlayer) {
        // player should trigger events on its own
        utterance.attachedPlayer.pause();
      }
    };
    this.resumeSpeaking = function() {
      if(utterance.attachedPlayer) {
        // player should trigger events on its own
        utterance.attachedPlayer.resume();
      }
    };
  
    var listeners = {};
    this.bind = function(event, callback) {
      listeners[event] = listeners[event] || [];
      listeners[event].push(callback);
    };
    this.addEventListener = this.bind;
    this.unbind = function(event, callback) {
      if(listeners[event]) {
        var newList = [];
        for(var idx = 0; idx < listeners[event].length; idx++) {
          if(listeners[event][idx] != callback) {
            newList.push(listeners[event][idx]);
          }
        }
        listeners[event] = newList;
      }
    };
    this.removeEventListener = this.unbind;
    this.trigger = function(event, name) {
      if(utterance.startTime) {
        utterance.elapsedTime = ((new Date()) - utterance.startTime) / 1000;
      }
      var eventObject = {
        charIndex: utterance.charIndex,
        elapsedTime: utterance.elapsedTime,
        name: name,
        utterance: utterance,
      };
      if(utterance['on' + event]) {
        utterance['on' + event](eventObject);
      }
      if(listeners[event]) {
        for(var idx = 0; idx < listeners[event].length; idx++) {
          listeners[event][idx](eventObject);
        }
      }
    }
  }
  function PolySpeechSynthesisVoice(voiceURI, name, lang, localService, def) {
    this.voiceURI = voiceURI;
    this.name = name;
    this.lang = lang;
    this.localService = localService;
    this.default = def;
  }

  function triggerActualSpeechSynthesis(utterance) {
    var voice = scope.speechSynthesis.voiceList.find(function(v) { v.voiceURI == utterance.voiceURI; });
    if((voice && voice.voiceURI == "voice:speak_js") || scope.speechSynthesis.voiceList.length == 1) {
      defaultUtteranceHandler(utterance);
    } else if(coughDropExtras.ready) {
      coughDropExtras.tts.speak(utterance);
    } else {
      console.log("vocalized: " + utterance.text);
      utterance.endSpeaking();
    }
  }
  
  scope.SpeechSynthesis = PolySpeechSynthesis;
  scope.SpeechSynthesisUtterance = PolySpeechSynthesisUtterance;
  var synthesis = new PolySpeechSynthesis();
  scope.speechSynthesis = synthesis;
  
  var defaultUtteranceHandler = null;

  var cloud_speak = function(utterance) {
    if(!navigator.onLine) {
      modal.error(i18n.t('offline_no_speech', "Your browser requires an Internet connection in order to generate speech"));
      return;
    }
    // TODO: make this an ajax call requiring API token instead to prevent abuse
    document.getElementById("audio").innerHTML=("<audio id=\"player\" src=\"/api/v1/search/audio?text="+encodeURIComponent(utterance.text)+"\">");
    var event_handler = utterance.trigger;
    var player = document.getElementById("player");
    
    if(event_handler) {
      player.addEventListener('play', function() {
        if(event_handler.alreadyStarted) {
          event_handler('resume');
        } else {
          event_handler.alreadyStarted = true;
          event_handler('start');
        }
      });
      player.addEventListener('ended', function() {
        event_handler('end');
      });
      player.addEventListener('pause', function(event) {
        if(!event.target.ended) {
          event_handler('pause');
        }
      });
      player.addEventListener('error', function() {
        event_handler('error');
      });
    }
    player.play();
  };
  var wav_audio = {};
  if(window.Audio) {
    wav_audio = new Audio();
    wav_audio.src = "data:audio/x-wav;base64,UklGRjIAAABXQVZFZm10IBIAAAABAAEAQB8AAEAfAAABAAgAAABmYWN0BAAAAAAAAABkYXRhAAAAAA==";
    wav_audio.onerror = function() {
      scope.speechSynthesis.cloud_only = true;
      wav_audio.unsupported = true;
    };
    wav_audio.onplay = function() {
      wav_audio.unsupported = false;
    };
  }
  if(wav_audio.play) {
    wav_audio.play();
  } else {
    scope.speechSynthesis.cloud_only = true;
    wav_audio.unsupported = true;
  }

  // TODO: this won't work on all browsers, do a capability check
  if(window.speak) {
    synthesis.voiceList.push({
      voiceURI: "voice:speak_js",
      name: "Basic computer voice (male)",
      lang: "en",
      localService: true
    });
    defaultUtteranceHandler = function(utterance) {
      if(wav_audio.unsupported) {
        cloud_speak(utterance);
      } else {
        speak(utterance.text, {
          amplitude: Math.max(((utterance.volume || 1.0) * 100), 0.01),
          pitch: Math.max(((utterance.pitch || 1.0) * 50), 0.01),
          speed: ((utterance.rate || 1.0) * 175),
          event: function(eventType) {
            utterance.trigger(eventType);
          }
        });
      }
    }
    if(window.speecher) {
      window.speecher.check_readiness();
    }
  }
}
window.polyfillSpeechSynthesis = polyfillSpeechSynthesis;