import { Controller } from "@hotwired/stimulus"

// Positions a popover with its top/right aligned to its invoker button, and keeps
// it aligned while open as the page scrolls/resizes — so it tracks a sticky
// header the invoker lives in instead of detaching.
export default class extends Controller {
  static values = { placement: { type: String, default: "below" } }

  connect() {
    this.element.addEventListener("beforetoggle", this.onToggle)
  }

  disconnect() {
    this.element.removeEventListener("beforetoggle", this.onToggle)
    this.stopTracking()
  }

  onToggle = (event) => {
    if (event.newState === "open") {
      this.reposition()
      this.startTracking()
    } else {
      this.stopTracking()
    }
  }

  startTracking() {
    window.addEventListener("scroll", this.reposition, { passive: true })
    window.addEventListener("resize", this.reposition)
  }

  stopTracking() {
    window.removeEventListener("scroll", this.reposition)
    window.removeEventListener("resize", this.reposition)
  }

  reposition = () => {
    const trigger = document.querySelector(`[popovertarget="${this.element.id}"]`)
    if (!trigger) return
    const rect = trigger.getBoundingClientRect()
    const style = this.element.style
    if (this.placementValue === "centered") {
      // Centered on the trigger, dropping below it — except when the trigger
      // sits in the bottom 10% of the viewport, where below would clip, so
      // the panel opens upward instead.
      style.insetInlineStart = `${rect.left + rect.width / 2}px`
      style.translate = "-50% 0"
      style.insetInlineEnd = "auto"
      if (rect.bottom > document.documentElement.clientHeight * 0.9) {
        style.insetBlockEnd = `${document.documentElement.clientHeight - rect.top + 6}px`
        style.insetBlockStart = "auto"
      } else {
        style.insetBlockStart = `${rect.bottom + 6}px`
        style.insetBlockEnd = "auto"
      }
      return
    }
    if (this.placementValue === "above") {
      // "above" floats the panel over the trigger, horizontally centered on it —
      // for triggers that sit in the content flow rather than at the right edge.
      // The translate does the centering so the panel's width never needs
      // measuring (it's still display:none when this first runs).
      style.insetBlockEnd = `${document.documentElement.clientHeight - rect.top + 6}px`
      style.insetInlineStart = `${rect.left + rect.width / 2}px`
      style.translate = "-50% 0"
      style.insetBlockStart = "auto"
      style.insetInlineEnd = "auto"
      return
    }
    // "top" aligns the panel top with the trigger (covers it, e.g. canvas ⋯);
    // "below" drops it just under the trigger (dropdowns).
    const top = this.placementValue === "top" ? rect.top : rect.bottom + 6
    // clientWidth excludes the scrollbar; window.innerWidth would over-offset by it
    style.insetBlockStart = `${top}px`
    style.insetInlineEnd = `${document.documentElement.clientWidth - rect.right}px`
    // neutralize the UA's [popover] inset:0 — otherwise left:0 wins the
    // over-constrained fixed box and the panel pins to the screen edge
    style.insetInlineStart = "auto"
    style.insetBlockEnd = "auto"
  }
}
