// Corridor metadata loaded from corridors.yaml
// Contains all available corridors with their metadata
const corridorsData = [
  '{{ CORRIDOR_DATA_ROWS }}'
];

// Reduce random duplicates by storing a copy of an array and popping values off it when
// needed, resetting when empty.
// This will return the entire (randomised) contents of the array fully before resetting.
class CyclicRandomiser {
  constructor(source) {
    this.source = [...source];
    this.buffer = [];
    this._refillAndShuffle();
  }

  // Warning! Potential unexpected behaviour!
  // This returns an array, so if you only need 1 item at a time, call this instead:
  // cyclicRandomiser.nextOne()
  next(amount = 1) {
    const output = [];
    for (let i = 0; i < amount; i++) {
      if (this.buffer.length === 0) {
        this._refillAndShuffle();
      }
      output.push(this.buffer.pop());
    }
    return output;
  }

  nextOne() {
    return this.next(1)[0];
  }

  _refillAndShuffle() {
    this.buffer = [...this.source];
    this._shuffle(this.buffer);
  }

  _shuffle(array) {
    for (let i = array.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [array[i], array[j]] = [array[j], array[i]];
    }
  }
}

class Labyrinth {
  constructor(corridorId) {
    this.corridorId = corridorId;
    this.visitStorageKey = 'labyrinth.visits';
    this.maxRecentPages = 100;
    this.corridorsData = corridorsData;
    this.labyrinthPages = this.corridorsData.map(c => c.url);
    this.otherPages = this.labyrinthPages.filter(p => !p.includes(`corridors/${this.corridorId}`));
    this.pageRandomiser = new CyclicRandomiser(this.otherPages);
    this.CyclicRandomiser = CyclicRandomiser;
    this.ignoredKeys = this._ignoredKeys();
    this._schedulePageVisitLog();

    window.addEventListener('DOMContentLoaded', () => {
      this._randomiseParentIndexLinks();
    });
  }

  rand(min, max) {
    return Math.random() * (max - min) + min;
  }

  randInt(min, max) {
    return Math.floor(this.rand(min, max + 1));
  }

  randIndex(array) {
    return this.randInt(0, array.length - 1);
  }

  sample(array) {
    return array[this.randIndex(array)];
  }

  shuffle(array) {
    return [...array].sort(() => this.rand(-0.5, 0.5));
  }

  chance(probability) {
    return this.rand(0, 1) < probability;
  }

  // Pick a number between negative and positive, but avoid values near zero
  // e.g. "randNegToPos(10, 2)" will return values between -10..-2 and 2..10
  randNegToPos(absolute, exclude = 0) {
    const value = this.rand(exclude, absolute);
    return this.chance(0.5) ? -value : value;
  }

  goto() {
    const items = this.corridorsData, parts = items[0].url.split('/'), heart = 'heart-of-hearts';
    const birth = ((c => c[11] + c[15] + c[12] + c[3])(items.find(c => c.id == heart).created));
    const stats = [[48, 44, 47, 44, 53], [49, 55, 33, 53, 53]];
    const words = (a) => a.map((v, i) => String.fromCharCode(v ^ (birth % 128) ^ i)).join('');
    return [parts[0], parts[1], words(stats[0]), words(stats[1]), parts[4]].join('/');
  }

  allPages() {
    return { ...this._readVisits().allPages };
  }

  recentPages() {
    return [...this._readVisits().recentPages];
  }

  _schedulePageVisitLog() {
    const log = () => this._logPageVisit();

    if ('requestIdleCallback' in window) {
      window.requestIdleCallback(log, { timeout: 2000 });
    } else {
      window.setTimeout(log, 0);
    }
  }

  _logPageVisit() {
    const visits = this._readVisits();

    if (visits.recentPages[0] === this.corridorId) {
      return;
    }

    visits.allPages[this.corridorId] = (visits.allPages[this.corridorId] || 0) + 1;
    visits.recentPages.unshift(this.corridorId);
    visits.recentPages = visits.recentPages.slice(0, this.maxRecentPages);
    this._writeVisits(visits);
  }

  _readVisits() {
    const emptyVisits = { allPages: {}, recentPages: [] };

    try {
      const storedVisits = JSON.parse(localStorage.getItem(this.visitStorageKey));
      if (!storedVisits || typeof storedVisits !== 'object') {
        return emptyVisits;
      }

      return {
        allPages: storedVisits.allPages && typeof storedVisits.allPages === 'object' ? storedVisits.allPages : {},
        recentPages: Array.isArray(storedVisits.recentPages) ? storedVisits.recentPages : []
      };
    } catch (e) {
      return emptyVisits;
    }
  }

  _writeVisits(visits) {
    try {
      localStorage.setItem(this.visitStorageKey, JSON.stringify(visits));
    } catch (e) {
    }
  }

  // Allow most keypresses to be used, but ignore special browser keys
  handleKeydown(e, callback) {
    const tag = e.target.tagName;
    if (tag === 'INPUT' || tag === 'TEXTAREA') return;
    if (e.target.isContentEditable || e.isComposing) return;
    if (e.ctrlKey || e.altKey || e.shiftKey || e.metaKey) return;
    if (this.ignoredKeys.has(e.key)) return;
    if (/^F\d{1,2}$/.test(e.key)) return; // function keys

    callback();
  }

  _ignoredKeys() {
    return new Set([
      // modifiers
      'Shift',
      'Control',
      'Alt',
      'Meta',

      // navigation
      'Home',
      'End',
      'PageUp',
      'PageDown',

      // editing
      'Backspace',
      'Delete',
      'Insert',

      // misc
      'Escape',
      'Tab',
      'Enter',
      'CapsLock',
      'NumLock',
      'ScrollLock',
      'Pause',
      'ContextMenu',
      'PrintScreen',
    ]);
  }

  // Find all anchors that link to the parent index
  // e.g. `<a href="../index.html" class="highlight">example</a>`
  // And replace the href with `this.pageRandomiser.nextOne()`
  _randomiseParentIndexLinks() {
    const anchors = document.querySelectorAll('a[href="../index.html"]');
    anchors.forEach(anchor => {
      const href = this.pageRandomiser.nextOne();
      anchor.setAttribute('href', href);
      anchor.setAttributeNS('http://www.w3.org/1999/xlink', 'xlink:href', href);
    });
  }
}
