import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "query", "results", "selection", "summary" ]
  static values = { exclude: Number }

  search() {
    this.clearTimer()
    const query = this.queryTarget.value.trim()
    if (!query) { this.resultsTarget.replaceChildren(); return }
    this.timer = setTimeout(() => {
      fetch(`/persons/search?q=${encodeURIComponent(query)}`, { headers: { Accept: "application/json" } })
        .then((response) => response.json())
        .then((data) => {
          const matches = data.persons.filter((person) => person.id !== this.excludeValue)
          this.resultsTarget.replaceChildren(...matches.map((person) => {
            const button = document.createElement("button")
            button.type = "button"
            button.className = "pickerResult"
            const summary = document.createElement("span")
            summary.className = "personSummary"
            const name = document.createElement("span")
            name.textContent = person.name || "Unnamed person"
            summary.append(name)
            const count = document.createElement("span")
            count.textContent = `${person.face_count} faces`
            button.append(summary, count)
            button.addEventListener("click", () => this.select(person))
            return button
          }))
        })
        .catch(() => this.resultsTarget.replaceChildren())
    }, 250)
  }

  select(person) {
    this.selectionTarget.value = person.id
    if (this.element.dataset.personPickerMergeUrl) {
      this.element.action = this.element.dataset.personPickerMergeUrl.replace(/\/\d+$/, `/${person.id}`)
    }
    if (this.hasSummaryTarget) {
      this.summaryTarget.textContent = `${person.name || "Unnamed person"} · ${person.face_count} faces`
    }
    this.resultsTarget.replaceChildren()
    this.queryTarget.value = ""
  }

  clearTimer() {
    if (this.timer) { clearTimeout(this.timer); this.timer = null }
  }

  disconnect() {
    this.clearTimer()
  }
}
