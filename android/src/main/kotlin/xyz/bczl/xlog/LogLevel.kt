package xyz.bczl.xlog

enum class LogLevel(val value: Int) {
    VERBOSE(0),
    DEBUG(1),
    INFO(2),
    WARNING(3),
    ERROR(4),
    FATAL(5),
    NONE(6);

    companion object {
        fun fromValue(value: Int): LogLevel =
            entries.firstOrNull { it.value == value } ?: NONE
    }
}
