const LocalTimeHook = {
  mounted() {
    this.format()
  },

  updated() {
    this.format()
  },

  format() {
    const datetime = this.el.getAttribute("datetime")
    if (!datetime) return
    const date = new Date(datetime + "Z")
    this.el.textContent = date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
  }
}

export default LocalTimeHook
