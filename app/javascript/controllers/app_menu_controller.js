import { Controller } from "@hotwired/stimulus"

// The app menu (jump-to sheet). The native Popover API handles open / Escape /
// click-outside dismiss; this adds type-to-filter and ↑/↓/Enter nav over the
// rows the server already rendered.
export default class extends Controller {
  static targets = ["input", "item", "group", "empty"]

  // Fired by the popover's toggle event: reset and focus the search on open.
  toggled(event) {
    if (event.newState !== "open") return
    this.inputTarget.value = ""
    this.filter()
    queueMicrotask(() => this.inputTarget.focus())
  }

  filter() {
    const query = this.inputTarget.value.trim().toLowerCase()

    this.itemTargets.forEach((item) => {
      item.hidden = query.length > 0 && !item.textContent.toLowerCase().includes(query)
    })
    this.groupTargets.forEach((group) => {
      group.hidden = group.querySelectorAll("[data-app-menu-target='item']:not([hidden])").length === 0
    })

    const visible = this.visibleItems
    if (this.hasEmptyTarget) this.emptyTarget.hidden = visible.length > 0
    this.activate(visible[0])
  }

  keydown(event) {
    const visible = this.visibleItems
    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.move(visible, 1)
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.move(visible, -1)
    } else if (event.key === "Enter") {
      event.preventDefault()
      ;(this.current || visible[0])?.click()
    }
    // Escape is handled by the native popover (light dismiss).
  }

  get visibleItems() {
    return this.itemTargets.filter((item) => !item.hidden)
  }

  get current() {
    return this.itemTargets.find((item) => item.classList.contains("is-active") && !item.hidden)
  }

  activate(item) {
    this.itemTargets.forEach((i) => i.classList.remove("is-active"))
    item?.classList.add("is-active")
  }

  move(visible, delta) {
    if (!visible.length) return
    const index = visible.indexOf(this.current)
    const next = visible[(index + delta + visible.length) % visible.length]
    this.activate(next)
    next.scrollIntoView({ block: "nearest" })
  }
}
