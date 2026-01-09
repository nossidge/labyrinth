// Reduce random duplicates by storing a copy of an array and popping values off it when
// needed, resetting when empty.
// This will return the entire (randomised) contents of the array fully before resetting.
class CyclicRandomiser {
  constructor(source) {
    this.source = [...source]
    this.buffer = []
    this._refillAndShuffle()
  }

  // Warning! Potential unexpected behaviour!
  // This returns an array, so if you only need 1 item at a time, call this instead:
  // cyclicRandomiser.nextOne()
  next(amount = 1) {
    const output = []
    for (let i = 0; i < amount; i++) {
      if (this.buffer.length === 0) {
        this._refillAndShuffle()
      }
      output.push(this.buffer.pop())
    }
    return output
  }

  nextOne() {
    return this.next(1)[0]
  }

  _refillAndShuffle() {
    this.buffer = [...this.source]
    this._shuffle(this.buffer)
  }

  _shuffle(array) {
    for (let i = array.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      // Semicolon in line above is necessary to prevent TDZ bug in this destructure assignment
      [array[i], array[j]] = [array[j], array[i]]
    }
  }
}
