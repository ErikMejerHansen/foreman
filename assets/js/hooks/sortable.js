import Sortable from "../../vendor/sortable.js"

const SortableHook = {
  mounted() {
    const status = this.el.dataset.status

    new Sortable(this.el, {
      group: "kanban",
      animation: 150,
      ghostClass: "opacity-30",
      dragClass: "shadow-lg",
      handle: "[data-task-id]",
      draggable: "[data-task-id]",
      onEnd: (evt) => {
        const taskId = evt.item.dataset.taskId
        const newStatus = evt.to.dataset.status

        if (taskId && newStatus) {
          this.pushEvent("move_task", {
            task_id: taskId,
            status: newStatus
          })
        }
      }
    })
  }
}

export default SortableHook
