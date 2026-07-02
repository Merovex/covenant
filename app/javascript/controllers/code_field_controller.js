import { Controller } from "@hotwired/stimulus"

// Drives a segmented sign-in code: one <input> per character (grouped 4 + 4),
// mirrored into a hidden `code` field that the form actually submits.
//
// - typing a letter advances to the next box; Backspace on an empty box steps back
// - paste distributes across every box, stripping hyphens/spaces and uppercasing
// - once all boxes are filled the form auto-submits (GitHub/Claude style)
export default class extends Controller {
  static targets = ["box", "hidden"]

  onInput(event) {
    const box = event.target
    const letters = box.value.replace(/[^a-zA-Z]/g, "").toUpperCase()
    box.value = letters.slice(-1) // one glyph per box; last keystroke wins
    if (box.value) this.nextBox(box)?.focus()
    this.sync()
  }

  onKeydown(event) {
    const box = event.target
    switch (event.key) {
      case "Backspace":
        if (box.value === "") {
          const prev = this.nextBox(box, -1)
          if (prev) { prev.value = ""; prev.focus(); this.sync() }
          event.preventDefault()
        }
        break
      case "ArrowLeft":
        this.nextBox(box, -1)?.focus()
        event.preventDefault()
        break
      case "ArrowRight":
        this.nextBox(box)?.focus()
        event.preventDefault()
        break
    }
  }

  onPaste(event) {
    event.preventDefault()
    const text = (event.clipboardData || window.clipboardData).getData("text")
    const letters = text.replace(/[^a-zA-Z]/g, "").toUpperCase().slice(0, this.boxTargets.length)

    this.boxTargets.forEach((box, i) => { box.value = letters[i] || "" })
    const landing = this.boxTargets[Math.min(letters.length, this.boxTargets.length - 1)]
    landing?.focus()
    this.sync()
  }

  sync() {
    const code = this.boxTargets.map((b) => b.value).join("")
    this.hiddenTarget.value = code
    if (code.length === this.boxTargets.length) this.element.closest("form")?.requestSubmit()
  }

  // Neighbour box in the given direction (+1 next, -1 previous), or undefined.
  nextBox(box, step = 1) {
    return this.boxTargets[this.boxTargets.indexOf(box) + step]
  }
}
