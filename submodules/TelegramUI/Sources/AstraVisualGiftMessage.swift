import Foundation
import Display
import TelegramCore
import AccountContext
import GiftViewScreen

/// AstraGram: the screen of a visual gift from its chat message: Telegram's gift screen with the giver and the date, and
/// no purchase, conversion or display buttons (a visual gift has none of these).
func astraOpenVisualGiftMessage(context: AccountContext, gift: StarGift.Gift, giver: EnginePeer?, ownerId: EnginePeer.Id, date: Int32, push: @escaping (ViewController) -> Void) {
    let item = ProfileGiftsContext.State.StarGift(
        gift: .generic(gift),
        reference: nil,
        fromPeer: giver,
        date: date,
        text: nil,
        entities: nil,
        nameHidden: giver == nil,
        savedToProfile: true,
        pinnedToTop: false,
        convertStars: nil,
        canUpgrade: false,
        canExportDate: nil,
        upgradeStars: nil,
        transferStars: nil,
        canTransferDate: nil,
        canResaleDate: nil,
        collectionIds: nil,
        prepaidUpgradeHash: nil,
        upgradeSeparate: false,
        dropOriginalDetailsStars: nil,
        number: nil,
        isRefunded: false,
        canCraftAt: nil
    )
    let isRussian = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode.astraUsesRussianTexts
    let controller = GiftViewScreen(
        context: context,
        subject: .profileGift(ownerId, item),
        customAction: GiftViewScreen.CustomAction(title: isRussian ? "Подарок AstraGram — понятно" : "AstraGram Gift — OK", action: {})
    )
    push(controller)
}
