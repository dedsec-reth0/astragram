// @id          astra-tools
// @name        AstraTools
// @version     1.0
// @author      AstraGram for iOS
// @description Команды: .rev текст, .upper текст, .calc 2+2*2, .count — счётчик отправленных через плагин сообщений

plugin.commands.rev = function (args) {
    return args.split("").reverse().join("")
}

plugin.commands.upper = function (args) {
    return args.toUpperCase()
}

plugin.commands.calc = function (args) {
    if (!/^[0-9+\-*/().,\s%]+$/.test(args)) {
        return "calc: только цифры и + - * / ( ) %"
    }
    try {
        return args + " = " + Function("return (" + args.replace(/,/g, ".") + ")")()
    } catch (e) {
        return "calc: ошибка"
    }
}

plugin.commands.count = function () {
    var count = (astra.storage.get("count") || 0) + 1
    astra.storage.set("count", count)
    return "Отправлено через AstraTools: " + count
}
