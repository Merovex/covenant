import { Controller } from "@hotwired/stimulus"

// A native <datalist> typeahead for picking a customer by name while the form
// still submits their id. The visible text input filters the datalist as you
// type; when its value matches an option, we copy that option's data-id into
// the hidden customer_id field (cleared when it doesn't match).
export default class extends Controller {
  static targets = ["input", "hidden", "list"]

  resolve() {
    const value = this.inputTarget.value.trim()
    const match = Array.from(this.listTarget.options).find((o) => o.value === value)
    this.hiddenTarget.value = match ? match.dataset.id : ""
  }
}
