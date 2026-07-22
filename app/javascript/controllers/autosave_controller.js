import { Controller } from "@hotwired/stimulus"

const PREFIX = "covenant/autosave/"
const MAX_AGE_MS = 30 * 24 * 60 * 60 * 1000 // stale drafts sweep out after 30 days
const DEBOUNCE_MS = 300

// Drafts a form's fields into localStorage as the user types and restores
// them the next time the form renders, so abandoning mid-thought (a
// mis-clicked "Never mind", a closed tab) never loses work. The server never
// sees these drafts.
//
// Key the draft to the identity being written about, not the form:
// data-autosave-key-value, e.g. "Record/42/comment" (new comment under
// record 42) or "Record/42/edit". The draft clears only on successful
// submit — abandoning is deliberately a no-op.
//
// Edit forms also pass data-autosave-revision-value (the record's current
// version id): a draft taken against a version that has since changed is
// stale and gets dropped rather than clobbering newer content.
export default class extends Controller {
  static values = { key: String, revision: String }

  connect() {
    this.write = this.write.bind(this)
    this.submitted = this.submitted.bind(this)
    this.element.addEventListener("input", this.write)
    this.element.addEventListener("lexxy:change", this.write)
    this.element.addEventListener("turbo:submit-end", this.submitted)

    this.prune()
    this.restore()
  }

  disconnect() {
    this.element.removeEventListener("input", this.write)
    this.element.removeEventListener("lexxy:change", this.write)
    this.element.removeEventListener("turbo:submit-end", this.submitted)

    // A pending debounce means unsnapshotted keystrokes — flush them, unless
    // the form just submitted successfully and the draft is already gone.
    if (this.timer) this.persist()
  }

  write() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.persist(), DEBOUNCE_MS)
  }

  submitted(event) {
    if (!event.detail.success) return

    clearTimeout(this.timer)
    this.timer = null
    localStorage.removeItem(this.storageKey)
  }

  persist() {
    this.timer = null

    const fields = {}
    for (const field of this.fields()) fields[field.name] = field.value

    if (Object.values(fields).every(value => this.blank(value))) {
      localStorage.removeItem(this.storageKey)
    } else {
      localStorage.setItem(this.storageKey, JSON.stringify(
        { revision: this.revisionValue, savedAt: Date.now(), fields }))
    }
  }

  restore() {
    const draft = this.read()
    if (!draft) return

    if ((draft.revision || "") !== this.revisionValue) {
      localStorage.removeItem(this.storageKey) // record moved on; draft is stale
      return
    }

    for (const field of this.fields()) {
      const value = draft.fields[field.name]
      if (value == null) continue

      if (field.tagName === "LEXXY-EDITOR") {
        this.setEditorValue(field, value)
      } else {
        field.value = value
      }
    }
  }

  read() {
    const raw = localStorage.getItem(this.storageKey)
    if (!raw) return null
    try {
      return JSON.parse(raw)
    } catch {
      localStorage.removeItem(this.storageKey)
      return null
    }
  }

  // Lexxy builds its editor synchronously on connect but a restore can still
  // beat the custom element upgrade — wait for lexxy:initialize if so.
  setEditorValue(editorElement, html) {
    if (editorElement.editor) {
      editorElement.value = html
    } else {
      editorElement.addEventListener("lexxy:initialize", () => { editorElement.value = html }, { once: true })
    }
  }

  // Writable fields physically inside the form: skips buttons, hidden inputs
  // (authenticity_token, _method) and scheduler-style controls that are only
  // form-associated via the form attribute.
  fields() {
    return [...this.element.querySelectorAll("input[name], textarea[name], select[name], lexxy-editor[name]")]
      .filter(field => !["hidden", "submit", "button", "password", "file"].includes(field.type))
  }

  // Blank if no text once tags collapse — but an attachment or image is
  // content even with no text around it.
  blank(value) {
    if (/<(action-text-attachment|img|figure)/.test(value)) return false
    return !value || !value.replace(/<[^>]*>|&nbsp;|\s/g, "")
  }

  prune() {
    for (const key of Object.keys(localStorage)) {
      if (!key.startsWith(PREFIX)) continue
      try {
        const { savedAt } = JSON.parse(localStorage.getItem(key))
        if (Date.now() - savedAt > MAX_AGE_MS) localStorage.removeItem(key)
      } catch {
        localStorage.removeItem(key)
      }
    }
  }

  get storageKey() {
    return PREFIX + this.keyValue
  }
}
