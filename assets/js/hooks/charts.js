import Chart from "../../vendor/chart.min"

Chart.defaults.color = "#9ca3af"
Chart.defaults.borderColor = "rgba(156, 163, 175, 0.15)"
Chart.defaults.font.family = "inherit"

export default {
  mounted() {
    this._charts = []
    this._render()
  },

  updated() {
    this._destroy()
    this._render()
  },

  destroyed() {
    this._destroy()
  },

  _render() {
    const configs = JSON.parse(this.el.getAttribute("data-charts") || "[]")
    configs.forEach((config, i) => {
      const wrapper = document.createElement("div")
      wrapper.className = "bg-base-100 border border-base-300 rounded-lg p-4"
      const inner = document.createElement("div")
      inner.style.position = "relative"
      inner.style.height = "220px"
      const canvas = document.createElement("canvas")
      canvas.id = `chart-${this.el.id}-${i}`
      inner.appendChild(canvas)
      wrapper.appendChild(inner)
      this.el.appendChild(wrapper)
      this._charts.push(new Chart(canvas, config))
    })
  },

  _destroy() {
    this._charts.forEach(c => c.destroy())
    this._charts = []
    while (this.el.firstChild) this.el.removeChild(this.el.firstChild)
  }
}
