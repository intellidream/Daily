package com.intellidream.daily.model

sealed class DashboardRow {
    abstract val id: String

    data class Full(val config: DashboardWidgetConfig) : DashboardRow() {
        override val id: String get() = "full-${config.id}"
    }

    data class Pair(val left: DashboardWidgetConfig, val right: DashboardWidgetConfig) : DashboardRow() {
        override val id: String get() = "pair-${left.id}-${right.id}"
    }

    data class TallWithSmalls(val tall: DashboardWidgetConfig, val smalls: List<DashboardWidgetConfig>) : DashboardRow() {
        override val id: String get() = "tall-${tall.id}-${smalls.joinToString("-") { it.id }}"
    }

    data class SingleSmall(val config: DashboardWidgetConfig) : DashboardRow() {
        override val id: String get() = "single-${config.id}"
    }
}

object DashboardRowBuilder {
    fun buildRows(configs: List<DashboardWidgetConfig>): List<DashboardRow> {
        val rows = mutableListOf<DashboardRow>()
        val remaining = configs.toMutableList()

        while (remaining.isNotEmpty()) {
            val current = remaining.removeAt(0)

            when (current.size) {
                DashboardWidgetSize.Wide, DashboardWidgetSize.Large -> {
                    rows.add(DashboardRow.Full(current))
                }

                DashboardWidgetSize.Small -> {
                    val nextSmallIndex = remaining.indexOfFirst { it.size == DashboardWidgetSize.Small }
                    if (nextSmallIndex >= 0) {
                        val partner = remaining.removeAt(nextSmallIndex)
                        rows.add(DashboardRow.Pair(current, partner))
                    } else {
                        val nextTallIndex = remaining.indexOfFirst { it.size == DashboardWidgetSize.Tall }
                        if (nextTallIndex >= 0) {
                            val tall = remaining.removeAt(nextTallIndex)
                            rows.add(DashboardRow.TallWithSmalls(tall = tall, smalls = listOf(current)))
                        } else {
                            rows.add(DashboardRow.SingleSmall(current))
                        }
                    }
                }

                DashboardWidgetSize.Tall -> {
                    val smalls = mutableListOf<DashboardWidgetConfig>()
                    while (smalls.size < 2) {
                        val smallIdx = remaining.indexOfFirst { it.size == DashboardWidgetSize.Small }
                        if (smallIdx >= 0) {
                            smalls.add(remaining.removeAt(smallIdx))
                        } else {
                            break
                        }
                    }

                    if (smalls.isNotEmpty()) {
                        rows.add(DashboardRow.TallWithSmalls(tall = current, smalls = smalls))
                    } else {
                        val nextTallIndex = remaining.indexOfFirst { it.size == DashboardWidgetSize.Tall }
                        if (nextTallIndex >= 0) {
                            val partner = remaining.removeAt(nextTallIndex)
                            rows.add(DashboardRow.Pair(current, partner))
                        } else {
                            rows.add(DashboardRow.SingleSmall(current))
                        }
                    }
                }
            }
        }

        return rows
    }
}
