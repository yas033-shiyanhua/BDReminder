//
//  BirthdayApp.swift（内容粘贴进工程的 BDReminderApp.swift）
//  BDReminder — 生日提醒 + 手工贺卡
//
//  部署说明：本文件内容与 ContentView.swift 一起，替换 BDReminder 工程自带的
//  BDReminderApp.swift / ContentView.swift 两个文件的内容即可
//  （GENERATE_INFOPLIST_FILE=YES，iOS 26，Swift 5）。数据层为自有 JSON 存储，
//  不依赖 SwiftData，无论工程 Storage 选了什么都无关。
//  无第三方依赖，仅用 Apple 框架。
//
//  需要在 Xcode 工程设置（Info / Privacy）里手动添加的权限说明文案
//  （已通过 pbxproj 的 INFOPLIST_KEY_* 加好，见工程文件）：
//    NSContactsUsageDescription          —— 从通讯录导入联系人的生日、邮箱和电话
//    NSCalendarsUsageDescription         —— 把联系人生日添加进系统日历
//    NSCalendarsFullAccessUsageDescription —— 同上（requestFullAccessToEvents 必需此键）
//    NSMicrophoneUsageDescription        —— 录联系人「关于 TA」语音笔记（2026-11-03 已加进工程）
//    NSSpeechRecognitionUsageDescription —— 把语音笔记转写成文字（2026-11-03 已加进工程）
//  相册选图走 PhotosPicker，不需要相册权限键。
//  通知权限通过 UNUserNotificationCenter 在 App 内申请，无需 Info.plist 键。
//

import SwiftUI
import UIKit
import AVKit
import AVFoundation
import Foundation
import Combine
import UserNotifications
import EventKit
import Contacts
import PhotosUI
import Vision
import CoreImage
import AVFoundation
import Speech

// MARK: - 语言（中英双语）

/// App 界面语言。选择存 UserDefaults 的 "appLanguage"：第一次打开时在
/// LanguagePickerView 里选一次，之后默认用它，设置页里可改。
/// 不用 String Catalog / NSLocalizedString：全 App 文案经 L() 走自带字符串表，
/// 切换立即生效，且非 View 代码（通知、引擎提示）也能取词。
enum AppLanguage: String, CaseIterable {
    case zh, en

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .zh
    }
}

/// 取词：键 = 中文原文。中文模式（或未选语言）原样返回；
/// 英文模式查 StringsEN 表，查不到回落中文原文，保证不露键、不崩。
func L(_ zh: String) -> String {
    guard AppLanguage.current == .en else { return zh }
    return StringsEN.table[zh] ?? zh
}

/// 月份展示名：中文「3月」，英文「Mar」（生日显示与月份选择器共用）
func monthDisplayName(_ month: Int) -> String {
    if AppLanguage.current == .en {
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return names[max(0, min(11, month - 1))]
    }
    return "\(month)月"
}

// MARK: - 主题（明黄简笔卡通）

extension Color {
    /// 0xRRGGBB → Color（sRGB）
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// 全 App 配色板：大色块平涂、黑粗线勾边、留白多——Ins 风简笔卡通。
/// 全册最多这 5 色，不用渐变、不用模糊软阴影。
enum AppTheme {
    static let sunny = Color(hex: 0xFFC400)      // 明黄：主填充
    static let sunnyDeep = Color(hex: 0xE0A800)  // 琥珀黄：小控件着色（纯明黄在小字/小图标上发飘，用它保可读性）
    static let ink = Color(hex: 0x141414)        // 近黑：勾线与文字
    static let paper = Color(hex: 0xFFFFFF)      // 纸白：底色与留白
    static let coral = Color(hex: 0xFF5A4E)      // 珊瑚红：点缀
    static let sky = Color(hex: 0x3E9BFF)        // 天蓝：点缀
}

/// 粗线卡片：大色块填充 + 2pt 黑边 + 右下实心偏移「硬阴影」。
/// 填充与阴影都画在 background 里，不占布局尺寸。
struct ChunkyCard: ViewModifier {
    var fill: Color = AppTheme.paper

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(AppTheme.ink)
                        .offset(x: 4, y: 4)
                    RoundedRectangle(cornerRadius: 16)
                        .fill(fill)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppTheme.ink, lineWidth: 2)
            }
    }
}

/// 主按钮：明黄大色块 + 黑粗边 + 硬阴影；按下时整颗往右下沉 2pt、
/// 阴影收成 1pt，像纸片被按实。
struct SunnyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .foregroundStyle(AppTheme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(AppTheme.ink)
                        .offset(x: pressed ? 1 : 3, y: pressed ? 1 : 3)
                    RoundedRectangle(cornerRadius: 14)
                        .fill(AppTheme.sunny)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AppTheme.ink, lineWidth: 2)
            }
            .offset(x: pressed ? 2 : 0, y: pressed ? 2 : 0)
    }
}

/// 次按钮：与主按钮同形，纸白填充。
struct InkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .foregroundStyle(AppTheme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(AppTheme.ink)
                        .offset(x: pressed ? 1 : 3, y: pressed ? 1 : 3)
                    RoundedRectangle(cornerRadius: 14)
                        .fill(AppTheme.paper)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AppTheme.ink, lineWidth: 2)
            }
            .offset(x: pressed ? 2 : 0, y: pressed ? 2 : 0)
    }
}

/// 全场黄底：List/Form 隐藏系统滚动底色，整屏铺明黄当「场」——
/// 内容改坐在白卡上（见 ChunkyRow），不再是系统灰白分组的样子。
struct SunnyScreen: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(AppTheme.sunny)
    }
}

/// 列表行白卡：纸白圆角 + 2pt 黑边，行与行之间靠行距留白分隔。
/// 行里不放偏移硬阴影（会被列表行裁掉）；扁平白 + 黑边就是卡通味。
struct ChunkyRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowBackground(
                RoundedRectangle(cornerRadius: 14)
                    .fill(AppTheme.paper)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.ink, lineWidth: 2))
                    .padding(.vertical, 3)
                    .padding(.horizontal, 2)
            )
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
    }
}

extension View {
    func sunnyScreen() -> some View { modifier(SunnyScreen()) }
    func chunkyRow() -> some View { modifier(ChunkyRow()) }
}

/// 英文字符串表：键 = 中文原文（与代码里 L("…") 的参数逐字对应），值 = 英文译文。
/// 带参数的文案用 %@ / %d（含位置参数 %n$）占位，代码侧用 String(format:) 拼。
enum StringsEN {
    static let table: [String: String] = [
        "🎂 即将到来的生日": "🎂 Upcoming Birthdays",
        "最近": "Next up",
        "还没有带生日的联系人": "No Contacts with Birthdays Yet",
        "去「联系人」添加或从通讯录导入吧。": "Add some in the Contacts tab, or import them from your address book.",
        "就是今天！": "It's today!",
        "还有 %d 天": "%d days to go",
        "将满 %d 岁": "Turning %d",
        "待补生日（点进去补上生日）": "Needs a Birthday (tap to add one)",
        "首页": "Home",
        "联系人": "Contacts",
        "搜索姓名或备注": "Search by name or note",
        "从通讯录导入": "Import from Contacts",
        "添加": "Add",
        "通讯录导入": "Contacts Import",
        "好": "OK",
        "未填生日": "No birthday",
        "今天": "Today",
        "%d 天后": "in %d days",
        "基本信息": "Basic Info",
        "姓名": "Name",
        "分组": "Group",
        "按字母": "Alphabet",
        "按分组": "Group",
        "星标": "Starred",
        "是": "Yes",
        "否": "No",
        "生日": "Birthday",
        "倒计时": "Countdown",
        "%d 岁": "%d years old",
        "将满": "Turning",
        "未填写": "Not set",
        "邮箱": "Email",
        "电话": "Phone",
        "备注": "Note",
        "关于 TA": "About Them",
        "可选：录一段语音或写几句你对 TA 的想法——为什么 TA 重要、TA 喜欢什么。以后选卡、选礼物时能翻出来看。不填也可以。": "Optional — record a voice note or write a few words about them: why they matter, what they like. It'll help when you pick a card or a gift. Fine to leave blank.",
        "加入系统日历": "Add to Calendar",
        "去做卡片": "Make a Card",
        "编辑联系人": "Edit Contact",
        "TA 的卡片池": "Their Card Pool",
        "还没有给 TA 准备的卡片，去做一张吧。": "No cards for them yet. Go make one!",
        "删除联系人": "Delete Contact",
        "日历": "Calendar",
        "联系人不存在": "Contact Not Found",
        "有生日": "Has a birthday",
        "月": "Month",
        "日": "Day",
        "%d日": "%d",
        "填写年份": "Include year",
        "年份：%d": "Year: %d",
        "年份": "Year",
        "合作伙伴": "Partners",
        "分组默认卡": "Group Default Cards",
        "给每个分组选一张现成的卡。组里谁过生日、又没单独给他准备卡，就用这张。": "Pick a ready-made card for each group. When someone in the group has a birthday and no personal card was prepared, this card is used.",
        "未设置": "Not Set",
        "不设置": "None",
        "卡片库还是空的，先去做一张卡。": "Your card library is empty — make a card first.",
        "分组默认卡 · %@": "Group default · %@",
        "管理本组": "Manage Group",
        "已选 %d/%d 人": "%d/%d selected",
        "已选 %d / %d 人会收到这张卡": "%d of %d selected will receive this card",
        "先给这个分组选一张默认卡": "Pick a default card for this group first",
        "全选": "Select All",
        "全不选": "Deselect All",
        "已备自己的卡": "Has own card",
        "这个分组还没有联系人。": "No contacts in this group yet.",
        "不填年份也可以，只记月和日。": "The year is optional — month and day are enough.",
        "分组与星标": "Group & Star",
        "星标（重要联系人）": "Starred (important contact)",
        "联系方式": "Contact Info",
        "备注（喜好、忌口等）": "Note (likes, dislikes, etc.)",
        "关于 TA（可选）": "About Them (Optional)",
        "想说说你对 TA 的想法吗？为什么 TA 重要、TA 喜欢什么——录一段语音或写下来，以后选卡、选礼物时能翻出来看。不填也可以。": "Say a little about them — why they matter, what they like. Record it or write it down; it'll help when you pick a card or a gift. Fine to leave blank.",
        "添加联系人": "Add Contact",
        "取消": "Cancel",
        "保存": "Save",
        "没有麦克风权限，请到系统「设置」里允许使用麦克风；也可以直接在下面打字记笔记。": "No microphone access. You can allow it in Settings, or just type your note below.",
        "没有麦克风权限，无法录音；可以直接在下面打字记笔记。": "No microphone access, so recording is unavailable. You can type your note below.",
        "麦克风权限状态未知，暂时无法录音。": "Microphone permission status is unknown. Recording is unavailable for now.",
        "录音启动失败，请再试一次。": "Recording failed to start. Please try again.",
        "录音启动失败：%@": "Recording failed to start: %@",
        "录音文件找不到了，可能已被删除。": "The recording file is missing. It may have been deleted.",
        "播放失败：%@": "Playback failed: %@",
        "未获得语音识别授权，录音已保存；可以在下面手动打字。": "Speech recognition isn't authorized. The recording is saved; you can type the note yourself.",
        "转写失败，录音已保存。": "Transcription failed. The recording is saved.",
        "停止录音": "Stop Recording",
        "正在录音……说说你对 TA 的想法吧，点「停止录音」结束。": "Recording… Say what they mean to you, then tap Stop Recording to finish.",
        "开始录音": "Start Recording",
        "重录（会替换现在的录音）": "Re-record (replaces the current one)",
        "停止播放": "Stop Playback",
        "播放录音": "Play Recording",
        "删除录音": "Delete Recording",
        "正在把录音转成文字……": "Transcribing…",
        "这是笔记，可以直接打字写；录音转写出来的文字会自动追加到末尾，不会盖掉已经写好的内容。": "Your note lives here. Type in it, or record — the transcript is appended at the end and never overwrites what's already written.",
        "回答几个小问题，帮我想想": "Answer a Few Questions",
        "你们怎么认识的？": "How did you meet?",
        "为什么 TA 对你重要？": "Why do they matter to you?",
        "TA 喜欢什么？": "What do they like?",
        "还有什么想记住的？": "Anything else worth remembering?",
        "第 %d / %d 问": "Question %d of %d",
        "想不到可以跳过，这一问不填也没关系。": "Can't think of anything? Skip it — blank is fine.",
        "跳过这一问": "Skip",
        "下一问": "Next",
        "完成": "Done",
        "问：%@\n答：%@": "Q: %@\nA: %@",
        "🎂 生日提醒": "🎂 Birthday Reminder",
        "今天是%@的生日，记得送上祝福！": "It's %@'s birthday today. Send them your wishes!",
        "还有%d天就是%@的生日（%d月%d日），提前准备一下吧。": "%2$@'s birthday is in %1$d days (%3$d/%4$d). Time to get ready!",
        "（模拟自动发送：到日子会提醒你确认发送）": " (Simulated auto-send: you'll be asked to confirm on the day.)",
        "💌 该发送贺卡了": "💌 Time to Send a Card",
        "现在是给%@发送贺卡「%@」的时间。": "It's time to send %1$@ the card \"%2$@\".",
        "现在是发送贺卡「%@」的时间。": "It's time to send the card \"%@\".",
        "%@还没有填写生日。": "%@ doesn't have a birthday yet.",
        "没有获得日历权限，请在系统设置里允许。": "No calendar access. Please allow it in Settings.",
        "已把「%@」加进系统日历，每年重复。": "Added \"%@\" to your calendar, repeating every year.",
        "「%@」已经在日历里了，没有重复添加。": "\"%@\" is already in your calendar — it wasn't added twice.",
        "保存到日历失败，请再试一次。": "Couldn't save to the calendar. Please try again.",
        "还没有带生日的联系人。": "No contacts have a birthday yet.",
        "已处理 %d 位联系人：新加 %d 位": "Done with %d contacts: %d added",
        "，已在日历里跳过 %d 位": ", %d already in the calendar",
        "，失败 %d 位": ", %d failed",
        "。": ".",
        "没有获得通讯录权限。可以在系统设置里允许，或手动添加联系人。": "No contacts access. You can allow it in Settings, or add contacts manually.",
        "读取通讯录失败：%@": "Couldn't read your contacts: %@",
        "导入完成：新增 %d 位，跳过重名 %d 位。没有生日的联系人在「待补生日」里。": "Import done: %d added, %d duplicates skipped. Contacts without a birthday are listed under \"Needs a Birthday\".",
        "做卡片": "Make a Card",
        "清空笔迹": "Clear Strokes",
        "清空": "Clear",
        "确定要清空所有笔迹吗？贴纸不会被清掉。": "Clear all strokes? Stickers stay.",
        "卡片库": "My Cards",
        "照片贴纸": "Photo Sticker",
        "照片做贴纸": "Photo Sticker",
        "纸张": "Paper",
        "画笔": "Brush",
        "撤销": "Undo",
        "颜色": "Color",
        "贴纸与文字": "Stickers & Text",
        "抠图中…": "Cutting out…",
        "点选元素后可拖动、双指缩放和旋转。": "Select an element to drag, pinch or rotate it.",
        "在画布上作画，点「完成」后笔迹会变成可移动的图层。": "Draw on the canvas. Tap Done to turn your strokes into a movable layer.",
        "已选元素": "Selected Element",
        "上移一层": "Bring Forward",
        "下移一层": "Send Backward",
        "删除": "Delete",
        "动态": "Motion",
        "悬浮": "Float",
        "不动": "Still",
        "悬浮像小幽灵一样慢慢左右晃；不动就完全静止。": "Float sways slowly side to side, like a little ghost. Still doesn't move at all.",
        "晃法": "Style",
        "左右": "Side to Side",
        "上下": "Up & Down",
        "左右+上下": "Drift",
        "摇摆": "Rocking",
        "幅度": "Amount",
        "复制": "Duplicate",
        "祝福语": "Greeting",
        "翻转": "Flip",
        "已翻转": "Flipped",
        "透明度": "Opacity",
        "打电话": "Call",
        "发短信": "Text",
        "发邮件": "Email",
        "模板": "Templates",
        "经典生日": "Classic Birthday",
        "樱花粉": "Sakura Pink",
        "极简": "Minimal",
        "加气泡": "Add Speech Bubble",
        "气泡里的话": "Words in the bubble",
        "圆点": "Dot",
        "卡片形式": "Card Format",
        "一张纸": "Single Sheet",
        "对折打开": "Folded (Opens)",
        "四折打开": "Quarter Fold",
        "封面": "Cover",
        "内页": "Inside",
        "内页左": "Inside Left",
        "内页右": "Inside Right",
        "背面": "Back",
        "打开卡片": "Open Card",
        "摇一个灵感": "Surprise Me",
        "灵感": "Inspiration",
        "这张照片怎么用？": "How do you want to use this photo?",
        "抠图做贴纸": "Cut Out as Sticker",
        "直接用原图": "Use Original Photo",
        "帧动画": "Frame Animation",
        "拍一帧": "Snap Frame",
        "播放": "Play",
        "暂停": "Pause",
        "播放动画": "Play Animation",
        "速度": "Speed",
        "慢": "Slow",
        "中": "Medium",
        "快": "Fast",
        "共 %d 帧": "%d frames in total",
        "删除这一帧": "Delete Frame",
        "总时长 %.1f 秒": "Total %.1f s",
        "点一帧选中，拖它的右边缘拉长或缩短": "Tap a frame to select it; drag its right edge to stretch or shrink it",
        "字号": "Font Size",
        "保存卡片": "Save Card",
        "卡片名称（可不填）": "Card name (optional)",
        "送给（卡片池）": "For (Card Pool)",
        "不指定": "Not assigned",
        "保存到卡片库": "Save to My Cards",
        "写一句祝福语，如：生日快乐！": "Write a greeting, e.g. Happy Birthday!",
        "生日快乐！": "Happy Birthday!",
        "加祝福语": "Add a Greeting",
        "还没有贴纸": "No Stickers Yet",
        "先用「照片做贴纸」抠一张，做好后会出现在这里，以后做新卡可以直接选。": "Cut one out with Photo Sticker first. It will appear here, ready to drop onto new cards.",
        "我的贴纸": "My Stickers",
        "关闭": "Close",
        "没有读到这张照片，请换一张试试。": "Couldn't read that photo. Try another one.",
        "这张照片抠图失败（可能没识别到清晰的主体），请换一张主体清楚的照片。": "Couldn't cut out this photo (no clear subject found). Try a photo with a clearer subject.",
        "读取照片失败：%@": "Couldn't read the photo: %@",
        "保存失败，请再试一次。": "Save failed. Please try again.",
        "保存失败：%@": "Save failed: %@",
        "我的卡片 %@": "My Card %@",
        "保存失败（存储空间可能不足），请再试一次。": "Save failed (storage may be full). Please try again.",
        "已保存「%@」到卡片库。": "Saved \"%@\" to My Cards.",
        "未命名卡片": "Untitled Card",
        "卡片库还是空的": "No Cards Yet",
        "去「做卡片」做第一张吧。": "Make your first one in Make a Card.",
        "图片文件已丢失": "Image file is missing",
        "归入卡片池": "Card Pool",
        "送给": "For",
        "定时发送（提醒）": "Send Reminder",
        "v1 先用提醒的方式：到时间通知你来发送这张卡。": "For now this is a reminder: you'll be notified when it's time to send this card.",
        "发送时间": "Send time",
        "已设好提醒，到时间会通知你发送。": "Reminder set. You'll be notified when it's time to send.",
        "设置提醒失败，请确认已允许通知。": "Couldn't set the reminder. Check that notifications are allowed.",
        "在这个时间提醒我发送": "Remind Me to Send Then",
        "分享这张卡片": "Share This Card",
        "删除卡片": "Delete Card",
        "卡片详情": "Card Details",
        "确定要删除「%@」吗？图片文件也会一起删掉。": "Delete \"%@\"? Its image file will be deleted too.",
        "提示": "Note",
        "卡片不存在": "Card Not Found",
        "未查询": "Not checked",
        "普通联系人提前提醒": "Regular Contacts",
        "星标联系人提前提醒": "Starred Contacts",
        "当天": "On the day",
        "提前 %d 天": "%d days before",
        "每天提醒时间": "Daily Reminder Time",
        "提醒设置": "Reminder Settings",
        "提醒中心": "Reminder Hub",
        "今年想送什么 / 想说什么": "What to give / say this year",
        "跟随全局设置": "Follow global settings",
        "跟随分组": "Follow group",
        "提前提醒": "Remind in advance",
        "提醒时间": "Reminder time",
        "发送方式": "Send mode",
        "发卡": "Send Card",
        "去做一张卡": "Make a Card",
        "恢复跟随全局设置": "Reset to global settings",
        "这张卡就是今年要发的": "This is the card for this year",
        "点「发卡」进卡片详情，用原来的方式分享或定时发送；「发短信」会把今年那行预填进短信内容。": "Tap \"Send Card\" to open the card and share it or set a send reminder as before. \"Text\" opens a message with this year's line already filled in.",
        "现在生效：提前 %d 天，%02d:%02d，%@": "Now in effect: %d days before, %02d:%02d, %@",
        "现在生效：提前 %d 天，%02d:%02d，%@，每 %d 小时重复提醒": "Now in effect: %d days before, %02d:%02d, %@, repeating every %d hours",
        "只改这个人，不改别人；选「跟随全局设置」就恢复成设置页里的全局值。改完会自动重新安排 TA 的生日提醒。": "This only changes this person, no one else. Pick \"Follow global settings\" to go back to the global values in Settings. Their birthday reminder is rescheduled automatically after a change.",
        "改完设置会自动重新安排所有生日提醒。": "Changes reschedule all birthday reminders automatically.",
        "每个分组的发送方式": "Send Mode per Group",
        "「自动发送（模拟）」在 v1 里仍是提醒，只是提醒文案会注明模拟自动发送；真正的自动发送等接了邮件/短信通道再开。": "In v1, Auto-Send (Simulated) is still a reminder — it just says \"simulated\" on it. Real auto-send arrives once email/text sending is wired up.",
        "通知权限": "Notifications",
        "当前状态": "Status",
        "已允许": "Allowed",
        "未允许": "Not allowed",
        "请求通知权限": "Request Notification Access",
        "重新安排全部提醒": "Reschedule All Reminders",
        "系统日历": "System Calendar",
        "把所有生日加进系统日历": "Add All Birthdays to Calendar",
        "每个生日会建成每年重复的日历事件；已存在的会跳过，不重复添加。": "Every birthday becomes a yearly repeating event. Existing ones are skipped.",
        "关于": "About",
        "版本": "Version",
        "v0.1（本机版）": "v0.1 (on-device)",
        "联系人、卡片和设置都只存在这台手机里，不上传任何服务器。": "Contacts, cards and settings stay on this phone only. Nothing is uploaded anywhere.",
        "设置": "Settings",
        "已被拒绝（去系统设置打开）": "Denied (enable it in Settings)",
        "还没询问过": "Not asked yet",
        "临时允许": "Provisional",
        "临时会话": "Ephemeral",
        "未知": "Unknown",
        "家人": "Family",
        "朋友": "Friends",
        "客户": "Clients",
        "只提醒": "Remind Only",
        "自动发送（模拟）": "Auto-Send (Simulated)",
        "白卡纸": "White Cardstock",
        "牛皮纸": "Kraft Paper",
        "粉纸": "Pink Paper",
        "蓝纸": "Blue Paper",
        "奶油纸": "Cream Paper",
        "亮粉纸": "Glitter Paper",
        "水彩纸": "Watercolor Paper",
        "底纹纸": "Striped Paper",
        "蜡笔": "Crayon",
        "记号笔": "Marker",
        "亮粉笔": "Glitter Pen",
        "细线笔": "Fine Pen",
        "水彩笔": "Watercolor Brush",
        "持续提醒": "Keep Reminding",
        "重复提醒间隔": "Repeat Interval",
        "每 %d 小时": "Every %d hours",
        "开启后，如果一直没有确认，生日提醒会按所选间隔反复发送，直到你点通知上的「已祝福，停止提醒」，或点开通知进入 App 为止。": "When on, a birthday reminder keeps repeating at the chosen interval until you tap \"Done, stop reminding\" on the notification, or tap the notification to open the app.",
        "已祝福，停止提醒": "Done, stop reminding",
        "（再次提醒）": "(Reminder again)",
        "提醒一下：%@的生日是%d月%d日，别忘了送上祝福！": "Reminder: %@'s birthday is on %d/%d. Don't forget to send your wishes!",
        "相册选图": "From Album",
        "拍照": "Take Photo",
        "这台设备没有可用的相机。": "No camera is available on this device.",
        "相册选纸": "Album Paper",
        "拍纸": "Photo Paper",
        "自定义纸使用中": "Using custom paper",
        "这张照片处理失败，请换一张试试。": "Couldn't process this photo. Please try another one.",
        "站起来预览": "Stand-Up Preview",
        "结束预览": "End Preview",
        "包装": "Packaging",
        "不包装": "No Wrap",
        "信封": "Envelope",
        "礼盒": "Gift Box",
        "红信封": "Red Envelope",
        "粉信封": "Pink Envelope",
        "奶油信封": "Cream Envelope",
        "蓝信封": "Blue Envelope",
        "紫礼盒": "Purple Box",
        "金礼盒": "Gold Box",
        "青礼盒": "Teal Box",
        "酒红礼盒": "Burgundy Box",
        "点下面的装饰把它挂到包装上，拖动可以挪位置，点中后可以删除。": "Tap a decoration to hang it on the package. Drag to move it; tap one to select it, then remove it if you like.",
        "删除装饰": "Remove Decoration",
        "刷新预览": "Refresh Preview",
        "动画信": "Animated Letter",
        "开场白": "Opening Line",
        "信的内容": "The Letter",
        "走路贴纸": "Walking Sticker",
        "上方画面": "Top Media",
        "下方画面": "Bottom Media",
        "固定贴纸": "Fixed Stickers",
        "添加图片贴纸": "Add Photo Sticker",
        "添加emoji贴纸": "Add Emoji Sticker",
        "第 %d 个字时出现": "Appears at letter #%d",
        "已选一段视频": "A video is selected",
        "选图片": "Choose Photo",
        "选视频": "Choose Video",
        "没有读到这段视频，请换一段试试。": "Couldn't read this video. Please try another one.",
        "回忆": "Memory",
        "回忆文字（点开时显示）": "Memory text (shown when tapped)",
        "回忆照片": "Memory Photo",
        "保存动画信": "Save Animated Letter",
        "播放动画信": "Play Animated Letter",
        "旅程地图": "Journey Map",
        "保存旅程": "Save Journey",
        "开始旅程": "Start Journey",
        "站点数：%d": "Stops: %d",
        "选我的头像": "Pick My Photo",
        "背景": "Background",
        "纸白": "Paper",
        "明黄": "Yellow",
        "天蓝": "Sky",
        "加照片": "Add Photo",
        "换照片": "Change Photo",
        "录语音": "Record Voice",
        "正在录音……": "Recording…",
        "没有麦克风权限，无法录音。": "No microphone access — can't record.",
        "这一站想说的话": "A note for this stop",
        "删除这一站": "Delete This Stop",
        "点一个站点，给它放照片、语音和文字。": "Tap a stop to add a photo, voice note and text.",
        "上一站": "Previous",
        "下一站": "Next",
        "打开这一站": "Open This Stop",
        "第 %d / %d 站": "Stop %d of %d",
        "这一站还没有放东西。": "Nothing here yet.",
        "我的旅程": "My Journey",
        "重播": "Replay",
        "选贴纸": "Choose a Sticker",
        "清除": "Clear",
        "点贴纸可以打开里面的回忆": "Tap a sticker to open the memory inside",
        "导出视频": "Export as Video",
        "导出网页（可点贴纸）": "Export as Web Page (tappable stickers)",
        "正在生成…": "Generating…",
        "生成失败，请再试一次。": "Generation failed. Please try again.",
    ]
}

/// 第一次打开 App 时的语言选择页：双语并列显示，选完写入 AppStorage 即进主界面。
struct LanguagePickerView: View {
    @AppStorage("appLanguage") private var appLanguage: String = ""

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Text("🎂").font(.system(size: 64))
            Text("请选择语言 / Choose your language")
                .font(.headline)
                .multilineTextAlignment(.center)
            VStack(spacing: 14) {
                Button {
                    appLanguage = AppLanguage.zh.rawValue
                } label: {
                    Text("中文版")
                        .font(.title3).bold()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    appLanguage = AppLanguage.en.rawValue
                } label: {
                    Text("English")
                        .font(.title3).bold()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding(32)
    }
}

// MARK: - App 入口

@main
struct BDReminderApp: App {
    @StateObject private var contactStore = ContactStore()
    @StateObject private var cardStore = CardStore()
    @StateObject private var settingsStore = SettingsStore()

    @AppStorage("appLanguage") private var appLanguage: String = ""

    init() {
        // 启动即注册通知分类与代理：用户点通知或点「已祝福，停止提醒」时，
        // 能把这位联系人还没发的后续重复提醒整串取消
        NotificationManager.shared.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            if appLanguage.isEmpty {
                // 第一次打开：先选一次语言，选完存下来，之后默认用它
                LanguagePickerView()
            } else {
                ContentView()
                    .environmentObject(contactStore)
                    .environmentObject(cardStore)
                    .environmentObject(settingsStore)
                    // 系统控件（日期/时间选择器等）的显示语言跟随所选语言
                    .environment(\.locale, Locale(identifier: appLanguage == AppLanguage.en.rawValue ? "en_US" : "zh_CN"))
                    // 切换语言时整棵界面树重建，所有 L() 文案立即换语言
                    .id(appLanguage)
            }
        }
    }
}

// MARK: - 基础模型

/// 生日：月/日必填，年份可选
struct BirthdayDate: Codable, Equatable {
    var year: Int?
    var month: Int
    var day: Int

    init(year: Int? = nil, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        year = try c.decodeIfPresent(Int.self, forKey: .year)
        month = try c.decodeIfPresent(Int.self, forKey: .month) ?? 1
        day = try c.decodeIfPresent(Int.self, forKey: .day) ?? 1
    }

    var displayText: String {
        if AppLanguage.current == .en {
            if let y = year {
                return "\(monthDisplayName(month)) \(day), \(y)"
            }
            return "\(monthDisplayName(month)) \(day)"
        }
        if let y = year {
            return "\(y)年\(month)月\(day)日"
        }
        return "\(month)月\(day)日"
    }
}

enum ContactGroup: String, Codable, CaseIterable, Identifiable {
    case family = "家人"
    case friend = "朋友"
    case client = "客户"
    case partner = "合作伙伴"
    var id: String { rawValue }
}

enum SendMode: String, Codable, CaseIterable, Identifiable {
    case remindOnly = "只提醒"
    case autoSend = "自动发送（模拟）"
    var id: String { rawValue }
}

struct BContact: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var birthday: BirthdayDate?
    var email: String
    var phone: String
    var isStarred: Bool
    var group: ContactGroup
    var note: String
    var cardPoolIDs: [UUID]
    /// 「关于 TA」语音笔记文件名（Documents/voice/ 子目录下），没有则 nil
    var voiceNoteFile: String?
    /// 「关于 TA」笔记文字（可打字、录音转写追加、引导问答合并进来），没有则 nil
    var noteText: String?
    /// 是否接收所在分组的默认卡：在分组管理页里勾选，默认不勾——只有被选中的人才发分组卡
    var receivesGroupCard: Bool
    /// Batch 1：本人的提醒覆盖（nil = 跟随全局/分组设置，旧存档没有这些键时全是 nil）
    var reminderAdvanceDays: Int?
    var reminderHour: Int?
    var reminderMinute: Int?
    /// 本人的发送方式覆盖（SendMode.rawValue，nil = 跟随分组）
    var sendModeRaw: String?
    /// 本人的重复提醒间隔覆盖（小时，nil = 跟随全局）
    var nagIntervalHours: Int?
    /// Batch 1：今年想送什么 / 想说什么（一行，提醒那天显示在卡下面）
    var thisYearNote: String?

    init(id: UUID = UUID(), name: String, birthday: BirthdayDate? = nil,
         email: String = "", phone: String = "", isStarred: Bool = false,
         group: ContactGroup = .friend, note: String = "", cardPoolIDs: [UUID] = [],
         voiceNoteFile: String? = nil, noteText: String? = nil,
         receivesGroupCard: Bool = false,
         reminderAdvanceDays: Int? = nil, reminderHour: Int? = nil,
         reminderMinute: Int? = nil, sendModeRaw: String? = nil,
         nagIntervalHours: Int? = nil, thisYearNote: String? = nil) {
        self.id = id
        self.name = name
        self.birthday = birthday
        self.email = email
        self.phone = phone
        self.isStarred = isStarred
        self.group = group
        self.note = note
        self.cardPoolIDs = cardPoolIDs
        self.voiceNoteFile = voiceNoteFile
        self.noteText = noteText
        self.receivesGroupCard = receivesGroupCard
        self.reminderAdvanceDays = reminderAdvanceDays
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.sendModeRaw = sendModeRaw
        self.nagIntervalHours = nagIntervalHours
        self.thisYearNote = thisYearNote
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        birthday = try c.decodeIfPresent(BirthdayDate.self, forKey: .birthday)
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        isStarred = try c.decodeIfPresent(Bool.self, forKey: .isStarred) ?? false
        group = try c.decodeIfPresent(ContactGroup.self, forKey: .group) ?? .friend
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        cardPoolIDs = try c.decodeIfPresent([UUID].self, forKey: .cardPoolIDs) ?? []
        voiceNoteFile = try c.decodeIfPresent(String.self, forKey: .voiceNoteFile)
        noteText = try c.decodeIfPresent(String.self, forKey: .noteText)
        receivesGroupCard = try c.decodeIfPresent(Bool.self, forKey: .receivesGroupCard) ?? false
        // Batch 1：旧存档没有这些键时 decodeIfPresent 拿不到就默认 nil（跟随全局），不丢人；
        // 坏数据钳到合法范围，避免 Picker 无项可选或提醒时间非法
        let rawAdv = try c.decodeIfPresent(Int.self, forKey: .reminderAdvanceDays)
        reminderAdvanceDays = rawAdv.flatMap { ReminderSettings.advanceOptions.contains($0) ? $0 : nil }
        let rawHour = try c.decodeIfPresent(Int.self, forKey: .reminderHour)
        reminderHour = rawHour.map { min(23, max(0, $0)) }
        let rawMinute = try c.decodeIfPresent(Int.self, forKey: .reminderMinute)
        reminderMinute = rawMinute.map { min(59, max(0, $0)) }
        sendModeRaw = try c.decodeIfPresent(String.self, forKey: .sendModeRaw)
        let rawNag = try c.decodeIfPresent(Int.self, forKey: .nagIntervalHours)
        nagIntervalHours = rawNag.flatMap { ReminderSettings.nagIntervalOptions.contains($0) ? $0 : nil }
        thisYearNote = try c.decodeIfPresent(String.self, forKey: .thisYearNote)
    }
}

/// 包装方式：卡片做好之后装进信封或礼盒，包装本身也能选样式、挂装饰
enum PackageKind: String, CaseIterable, Identifiable {
    case none = "不包装"
    case envelope = "信封"
    case box = "礼盒"
    var id: String { rawValue }
}

enum EnvelopeStyle: String, CaseIterable, Identifiable {
    case red = "红信封"
    case pink = "粉信封"
    case cream = "奶油信封"
    case blue = "蓝信封"
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .red: return Color(red: 0.85, green: 0.36, blue: 0.33)
        case .pink: return Color(red: 0.96, green: 0.62, blue: 0.70)
        case .cream: return Color(red: 0.93, green: 0.87, blue: 0.72)
        case .blue: return Color(red: 0.45, green: 0.62, blue: 0.85)
        }
    }
}

enum BoxStyle: String, CaseIterable, Identifiable {
    case purple = "紫礼盒"
    case gold = "金礼盒"
    case teal = "青礼盒"
    case burgundy = "酒红礼盒"
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .purple: return Color(red: 0.55, green: 0.42, blue: 0.75)
        case .gold: return Color(red: 0.88, green: 0.68, blue: 0.28)
        case .teal: return Color(red: 0.25, green: 0.65, blue: 0.62)
        case .burgundy: return Color(red: 0.58, green: 0.22, blue: 0.30)
        }
    }
}

/// 挂在包装上的一个装饰（emoji + 在 300×300 包装台面上的位置）
struct PackageDecoration: Identifiable, Codable, Equatable {
    var id = UUID()
    var emoji: String
    var x: Double
    var y: Double
    var scale: Double = 1.0
    var rotation: Double = 0
}

/// 动画信里固定下来的一张贴纸：第几个字出现时它出现，之后不消失；
/// 点开它能展开一段回忆（文字 + 可选照片）
struct LetterFixedSticker: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: String = "emoji"     // "photo" = stickers/ 里的抠图文件；"emoji"
    var value: String = "🎈"       // 文件名或 emoji
    var appearAtStep: Int = 0      // 开场白第几个字出现时它出现（0 = 一开始就在）
    var x: Double = 0.5            // 相对位置 0...1（台面宽）
    var y: Double = 0.6            // 相对位置 0...1（台面高）
    var memoryText: String? = nil
    var memoryImageFile: String? = nil   // letters/ 子目录
    /// 圆点（bullet point）：true 时不看 kind/value，渲染成一个小圆点，
    /// 点开后在回忆页里看 memoryText（= 藏在气泡里的话）
    var isDot: Bool = false

    init(id: UUID = UUID(), kind: String = "emoji", value: String = "🎈",
         appearAtStep: Int = 0, x: Double = 0.5, y: Double = 0.6,
         memoryText: String? = nil, memoryImageFile: String? = nil,
         isDot: Bool = false) {
        self.id = id
        self.kind = kind
        self.value = value
        self.appearAtStep = appearAtStep
        self.x = x
        self.y = y
        self.memoryText = memoryText
        self.memoryImageFile = memoryImageFile
        self.isDot = isDot
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "emoji"
        value = try c.decodeIfPresent(String.self, forKey: .value) ?? "🎈"
        appearAtStep = try c.decodeIfPresent(Int.self, forKey: .appearAtStep) ?? 0
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0.5
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0.6
        memoryText = try c.decodeIfPresent(String.self, forKey: .memoryText)
        memoryImageFile = try c.decodeIfPresent(String.self, forKey: .memoryImageFile)
        // 旧存档没有 isDot 键：decodeIfPresent 拿不到就默认 false，老动画信照常解码
        isDot = try c.decodeIfPresent(Bool.self, forKey: .isDot) ?? false
    }
}

/// 动画信模板：开场白逐字打出（约 0.5 秒一个字），下面是一封信，
/// 信的上下可各放一段画面（照片或视频）；一张抠图贴纸随字走过；
/// 固定贴纸出现后不消失，点开能展开回忆
struct LetterTemplateData: Codable, Equatable {
    var titleText: String
    var letterText: String
    var topMediaFile: String? = nil       // letters/ 子目录
    var topMediaIsVideo: Bool = false
    var bottomMediaFile: String? = nil
    var bottomMediaIsVideo: Bool = false
    var walkerKind: String? = nil         // "photo" / "emoji" / nil
    var walkerValue: String? = nil
    var fixedStickers: [LetterFixedSticker] = []

    init(titleText: String, letterText: String,
         topMediaFile: String? = nil, topMediaIsVideo: Bool = false,
         bottomMediaFile: String? = nil, bottomMediaIsVideo: Bool = false,
         walkerKind: String? = nil, walkerValue: String? = nil,
         fixedStickers: [LetterFixedSticker] = []) {
        self.titleText = titleText
        self.letterText = letterText
        self.topMediaFile = topMediaFile
        self.topMediaIsVideo = topMediaIsVideo
        self.bottomMediaFile = bottomMediaFile
        self.bottomMediaIsVideo = bottomMediaIsVideo
        self.walkerKind = walkerKind
        self.walkerValue = walkerValue
        self.fixedStickers = fixedStickers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        titleText = try c.decodeIfPresent(String.self, forKey: .titleText) ?? ""
        letterText = try c.decodeIfPresent(String.self, forKey: .letterText) ?? ""
        topMediaFile = try c.decodeIfPresent(String.self, forKey: .topMediaFile)
        topMediaIsVideo = try c.decodeIfPresent(Bool.self, forKey: .topMediaIsVideo) ?? false
        bottomMediaFile = try c.decodeIfPresent(String.self, forKey: .bottomMediaFile)
        bottomMediaIsVideo = try c.decodeIfPresent(Bool.self, forKey: .bottomMediaIsVideo) ?? false
        walkerKind = try c.decodeIfPresent(String.self, forKey: .walkerKind)
        walkerValue = try c.decodeIfPresent(String.self, forKey: .walkerValue)
        fixedStickers = try c.decodeIfPresent([LetterFixedSticker].self, forKey: .fixedStickers) ?? []
    }
}

/// 旅程地图上的一个站点：位置用 0…1 相对坐标（与画布实际尺寸无关），
/// 站里可以放一张照片、一段语音、一段文字，点开像翻翻书一样看
struct JourneyStop: Identifiable, Codable, Equatable {
    var id = UUID()
    var x: Double = 0.5            // 相对位置 0...1（画布宽）
    var y: Double = 0.5            // 相对位置 0...1（画布高）
    var photoFile: String? = nil   // journeys/ 子目录
    var voiceFile: String? = nil   // journeys/ 子目录
    var text: String? = nil

    init(id: UUID = UUID(), x: Double = 0.5, y: Double = 0.5,
         photoFile: String? = nil, voiceFile: String? = nil, text: String? = nil) {
        self.id = id
        self.x = x
        self.y = y
        self.photoFile = photoFile
        self.voiceFile = voiceFile
        self.text = text
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0.5
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0.5
        photoFile = try c.decodeIfPresent(String.self, forKey: .photoFile)
        voiceFile = try c.decodeIfPresent(String.self, forKey: .voiceFile)
        text = try c.decodeIfPresent(String.self, forKey: .text)
    }
}

/// 旅程地图模板：一张地图、几个站点、一个顶着发送者头像的火柴人，
/// 从第一站走到最后一站，每站都能打开看里面的照片 / 语音 / 文字
struct JourneyData: Codable, Equatable {
    var stops: [JourneyStop] = []
    var headFile: String? = nil        // 发送者头像照片，journeys/ 子目录
    var backgroundRaw: String = "paper"   // "paper" / "sunny" / "sky"，对应 AppTheme 纸白 / 明黄 / 天蓝

    init(stops: [JourneyStop] = [], headFile: String? = nil, backgroundRaw: String = "paper") {
        self.stops = stops
        self.headFile = headFile
        self.backgroundRaw = backgroundRaw
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stops = try c.decodeIfPresent([JourneyStop].self, forKey: .stops) ?? []
        headFile = try c.decodeIfPresent(String.self, forKey: .headFile)
        backgroundRaw = try c.decodeIfPresent(String.self, forKey: .backgroundRaw) ?? "paper"
    }
}

struct CardDesign: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var imageFile: String
    var createdAt: Date
    var assignedContactID: UUID?
    /// 包装（存 PackageKind/样式的 rawValue 字符串，落盘值不随语言变）
    var packageKind: String?
    var packageStyle: String?
    var decorations: [PackageDecoration]?
    /// 动画信模板（有值 = 这张卡可以播放动画信）
    var letter: LetterTemplateData?
    /// 帧动画：拍帧时逐帧渲染的 PNG 文件名（存 frames/ 子目录）；空 = 这张卡没有帧动画
    var frameFiles: [String] = []
    /// 帧动画：每一帧停留的秒数，与 frameFiles 逐项对齐（时间线上拖出来的）；缺项播放时按 0.35 兜底
    var frameDurations: [Double] = []
    /// 旅程地图模板（有值 = 这张卡可以开始旅程）
    var journey: JourneyData?

    init(id: UUID = UUID(), name: String, imageFile: String,
         createdAt: Date = Date(), assignedContactID: UUID? = nil,
         packageKind: String? = nil, packageStyle: String? = nil,
         decorations: [PackageDecoration]? = nil,
         letter: LetterTemplateData? = nil,
         frameFiles: [String] = [],
         frameDurations: [Double] = [],
         journey: JourneyData? = nil) {
        self.id = id
        self.name = name
        self.imageFile = imageFile
        self.createdAt = createdAt
        self.assignedContactID = assignedContactID
        self.packageKind = packageKind
        self.packageStyle = packageStyle
        self.decorations = decorations
        self.letter = letter
        self.frameFiles = frameFiles
        self.frameDurations = frameDurations
        self.journey = journey
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? L("未命名卡片")
        imageFile = try c.decodeIfPresent(String.self, forKey: .imageFile) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        assignedContactID = try c.decodeIfPresent(UUID.self, forKey: .assignedContactID)
        packageKind = try c.decodeIfPresent(String.self, forKey: .packageKind)
        packageStyle = try c.decodeIfPresent(String.self, forKey: .packageStyle)
        decorations = try c.decodeIfPresent([PackageDecoration].self, forKey: .decorations)
        letter = try c.decodeIfPresent(LetterTemplateData.self, forKey: .letter)
        frameFiles = try c.decodeIfPresent([String].self, forKey: .frameFiles) ?? []
        frameDurations = try c.decodeIfPresent([Double].self, forKey: .frameDurations) ?? []
        journey = try c.decodeIfPresent(JourneyData.self, forKey: .journey)
    }
}

struct ReminderSettings: Codable, Equatable {
    var advanceDays: Int
    var starredAdvanceDays: Int
    var reminderHour: Int
    var reminderMinute: Int
    /// key = ContactGroup.rawValue, value = SendMode.rawValue
    var groupModes: [String: String]
    /// 分组默认卡：key = ContactGroup.rawValue, value = 卡片 id。
    /// 组员没有单独准备的卡时，过生日就用这张；卡片被删后 id 查不到，读取处一律按未设置处理。
    var groupDefaultCardIDs: [String: UUID]
    /// 持续提醒：没确认就按间隔反复发，直到用户点通知确认
    var nagEnabled: Bool
    var nagIntervalHours: Int

    static let advanceOptions = [0, 1, 3, 7]
    static let nagIntervalOptions = [1, 2, 3, 4, 6]
    /// 一串持续提醒最多重复几次（封顶，避免无限排下去）
    static let nagMaxRepeats = 8

    static var defaults: ReminderSettings {
        ReminderSettings(
            advanceDays: 1,
            starredAdvanceDays: 3,
            reminderHour: 9,
            reminderMinute: 0,
            groupModes: [
                ContactGroup.family.rawValue: SendMode.remindOnly.rawValue,
                ContactGroup.friend.rawValue: SendMode.remindOnly.rawValue,
                ContactGroup.client.rawValue: SendMode.remindOnly.rawValue
            ],
            nagEnabled: true,
            nagIntervalHours: 3
        )
    }

    init(advanceDays: Int, starredAdvanceDays: Int, reminderHour: Int,
         reminderMinute: Int, groupModes: [String: String],
         nagEnabled: Bool = true, nagIntervalHours: Int = 3,
         groupDefaultCardIDs: [String: UUID] = [:]) {
        self.advanceDays = advanceDays
        self.starredAdvanceDays = starredAdvanceDays
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.groupModes = groupModes
        self.nagEnabled = nagEnabled
        self.nagIntervalHours = nagIntervalHours
        self.groupDefaultCardIDs = groupDefaultCardIDs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ReminderSettings.defaults
        let adv = try c.decodeIfPresent(Int.self, forKey: .advanceDays) ?? d.advanceDays
        let sAdv = try c.decodeIfPresent(Int.self, forKey: .starredAdvanceDays) ?? d.starredAdvanceDays
        // 范围钳制：坏数据不能让 Picker 无项可选、或让提醒时间非法
        advanceDays = ReminderSettings.advanceOptions.contains(adv) ? adv : d.advanceDays
        starredAdvanceDays = ReminderSettings.advanceOptions.contains(sAdv) ? sAdv : d.starredAdvanceDays
        reminderHour = min(23, max(0, try c.decodeIfPresent(Int.self, forKey: .reminderHour) ?? d.reminderHour))
        reminderMinute = min(59, max(0, try c.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? d.reminderMinute))
        groupModes = try c.decodeIfPresent([String: String].self, forKey: .groupModes) ?? d.groupModes
        groupDefaultCardIDs = try c.decodeIfPresent([String: UUID].self, forKey: .groupDefaultCardIDs) ?? [:]
        nagEnabled = try c.decodeIfPresent(Bool.self, forKey: .nagEnabled) ?? d.nagEnabled
        let interval = try c.decodeIfPresent(Int.self, forKey: .nagIntervalHours) ?? d.nagIntervalHours
        nagIntervalHours = ReminderSettings.nagIntervalOptions.contains(interval) ? interval : d.nagIntervalHours
    }

    func mode(for group: ContactGroup) -> SendMode {
        if let raw = groupModes[group.rawValue], let m = SendMode(rawValue: raw) {
            return m
        }
        return .remindOnly
    }

    func advance(for contact: BContact) -> Int {
        contact.isStarred ? starredAdvanceDays : advanceDays
    }

    /// Batch 1：本人覆盖优先，缺了就回落到全局/分组（nil = 跟随）
    func effectiveAdvance(for contact: BContact) -> Int {
        if let d = contact.reminderAdvanceDays, Self.advanceOptions.contains(d) { return d }
        return advance(for: contact)
    }

    func effectiveHour(for contact: BContact) -> Int {
        min(23, max(0, contact.reminderHour ?? reminderHour))
    }

    func effectiveMinute(for contact: BContact) -> Int {
        min(59, max(0, contact.reminderMinute ?? reminderMinute))
    }

    func effectiveMode(for contact: BContact) -> SendMode {
        if let raw = contact.sendModeRaw, let m = SendMode(rawValue: raw) { return m }
        return mode(for: contact.group)
    }

    func effectiveNagInterval(for contact: BContact) -> Int {
        if let h = contact.nagIntervalHours, Self.nagIntervalOptions.contains(h) { return h }
        return nagIntervalHours
    }
}

// MARK: - 文件存储

/// 逐条容错解码：一行坏数据只丢一行，不拖垮整库
private struct FailSafe<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

enum FileStorage {
    nonisolated static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    nonisolated static func url(for fileName: String, subdir: String? = nil) -> URL {
        var base = documentsURL
        if let sub = subdir {
            base = base.appendingPathComponent(sub, isDirectory: true)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base.appendingPathComponent(fileName)
    }

    @discardableResult
    static func saveJSON<T: Encodable>(_ value: T, to fileName: String) -> Bool {
        let url = documentsURL.appendingPathComponent(fileName)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return false }
        do {
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    /// 解码失败（文件存在但内容损坏）时先把原文件备份为 .corrupt 再返回 nil，
    /// 避免上层拿默认值/种子把它直接覆盖销毁
    private static func backupIfCorrupt(fileName: String) {
        let src = documentsURL.appendingPathComponent(fileName)
        let bak = documentsURL.appendingPathComponent(fileName + ".corrupt")
        let fm = FileManager.default
        if fm.fileExists(atPath: src.path) && !fm.fileExists(atPath: bak.path) {
            try? fm.copyItem(at: src, to: bak)
        }
    }

    static func loadJSON<T: Decodable>(_ type: T.Type, from fileName: String) -> T? {
        let url = documentsURL.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let value = try? decoder.decode(T.self, from: data) {
            return value
        }
        backupIfCorrupt(fileName: fileName)
        return nil
    }

    /// 数组专用：逐条容错，坏记录跳过；顶层结构坏了才整体返回 nil（并备份原文件）
    static func loadJSONArray<T: Decodable>(_ type: T.Type, from fileName: String) -> [T]? {
        let url = documentsURL.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let rows = try? decoder.decode([FailSafe<T>].self, from: data) {
            return rows.compactMap { $0.value }
        }
        backupIfCorrupt(fileName: fileName)
        return nil
    }

    /// 图片内存缓存：文件名都是 UUID、从不原地覆盖，缓存不会读到旧图；
    /// 编辑器里悬浮贴纸会高频重绘，不能每帧都读盘
    private static let imageCache = NSCache<NSString, UIImage>()

    static func loadImage(fileName: String, subdir: String? = nil) -> UIImage? {
        let key = ((subdir ?? "") + "/" + fileName) as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        let url = self.url(for: fileName, subdir: subdir)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        imageCache.setObject(image, forKey: key)
        return image
    }

    /// 贴纸库：stickers/ 下已存的贴纸文件名（最近做的在前）
    static func stickerFileNames() -> [String] {
        let dir = documentsURL.appendingPathComponent("stickers", isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        let pngs = names.filter { $0.lowercased().hasSuffix(".png") }
        return pngs.sorted { a, b in
            let da = (try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(a).path))?[.modificationDate] as? Date ?? .distantPast
            let db = (try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(b).path))?[.modificationDate] as? Date ?? .distantPast
            return da > db
        }
    }

    /// 安全删单个文件：只接受普通文件名（不带路径成分），且目标必须是已存在的文件
    /// 而不是目录；文件名为空/带路径/目标不存在时什么都不做（删录音、删贴纸等共用）
    static func deleteFile(fileName: String, subdir: String?) {
        guard !fileName.isEmpty,
              fileName == (fileName as NSString).lastPathComponent else { return }
        let url = self.url(for: fileName, subdir: subdir)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - 生日计算

enum BirthdayCalc {
    /// 闰日政策：2 月 29 日生日在平年按 3 月 1 日过（Calendar 对越界日期的归一化结果）。
    /// 倒计时、提醒、日历事件都走 dateInYear，三处口径一致。
    static func dateInYear(_ b: BirthdayDate, year: Int) -> Date? {
        var comps = DateComponents()
        comps.year = year
        comps.month = b.month
        comps.day = b.day
        comps.hour = 12
        return Calendar.current.date(from: comps)
    }

    /// 下一次生日（今天算起，含今天）
    static func nextBirthday(_ b: BirthdayDate, from today: Date = Date()) -> Date? {
        let cal = Calendar.current
        let thisYear = cal.component(.year, from: today)
        guard let candidate = dateInYear(b, year: thisYear) else { return nil }
        let startToday = cal.startOfDay(for: today)
        let startCandidate = cal.startOfDay(for: candidate)
        if startCandidate >= startToday {
            return candidate
        }
        return dateInYear(b, year: thisYear + 1)
    }

    static func daysUntil(_ b: BirthdayDate, from today: Date = Date()) -> Int? {
        guard let next = nextBirthday(b, from: today) else { return nil }
        let cal = Calendar.current
        let diff = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: today),
                                      to: cal.startOfDay(for: next))
        return diff.day
    }

    static func turningAge(_ b: BirthdayDate, from today: Date = Date()) -> Int? {
        guard let year = b.year, let next = nextBirthday(b, from: today) else { return nil }
        let nextYear = Calendar.current.component(.year, from: next)
        return nextYear - year
    }
}

// MARK: - Stores

final class ContactStore: ObservableObject {
    @Published var contacts: [BContact] = [] {
        didSet { persist() }
    }
    private let fileName = "contacts.json"
    private var isLoading = false

    init() {
        isLoading = true
        if let saved = FileStorage.loadJSONArray(BContact.self, from: fileName) {
            contacts = saved
        } else {
            contacts = ContactStore.seedContacts
        }
        isLoading = false
        persist()
    }

    private func persist() {
        guard !isLoading else { return }
        FileStorage.saveJSON(contacts, to: fileName)
    }

    static var seedContacts: [BContact] {
        [
            BContact(name: "林小雨",
                     birthday: BirthdayDate(year: 1995, month: 5, day: 12),
                     email: "xiaoyu@example.com", phone: "858-555-0112",
                     isStarred: true, group: .friend, note: "大学同学，喜欢花和猫"),
            BContact(name: "王建国",
                     birthday: BirthdayDate(year: 1968, month: 1, day: 3),
                     phone: "858-555-0103",
                     isStarred: true, group: .family, note: "舅舅"),
            BContact(name: "Sarah Chen",
                     birthday: BirthdayDate(year: nil, month: 11, day: 28),
                     email: "sarah@example.com",
                     group: .client, note: "工作联系人，年份未填")
        ]
    }

    func add(_ contact: BContact) {
        contacts.append(contact)
    }

    /// 批量添加（通讯录导入用）：一次赋值只落盘一次，避免逐条全量重写
    func addBatch(_ newContacts: [BContact]) {
        guard !newContacts.isEmpty else { return }
        contacts.append(contentsOf: newContacts)
    }

    func update(_ contact: BContact) {
        if let idx = contacts.firstIndex(where: { $0.id == contact.id }) {
            contacts[idx] = contact
        }
    }

    func delete(_ contact: BContact) {
        contacts.removeAll { $0.id == contact.id }
    }

    func contact(id: UUID?) -> BContact? {
        guard let id = id else { return nil }
        return contacts.first { $0.id == id }
    }

    var withBirthday: [BContact] {
        contacts.filter { $0.birthday != nil }
    }

    var withoutBirthday: [BContact] {
        contacts.filter { $0.birthday == nil }
    }

    var upcomingSorted: [BContact] {
        withBirthday.sorted {
            (BirthdayCalc.daysUntil($0.birthday!) ?? 9999) < (BirthdayCalc.daysUntil($1.birthday!) ?? 9999)
        }
    }
}

final class CardStore: ObservableObject {
    @Published var cards: [CardDesign] = [] {
        didSet { persist() }
    }
    private let fileName = "cards.json"
    private var isLoading = false

    init() {
        isLoading = true
        cards = FileStorage.loadJSONArray(CardDesign.self, from: fileName) ?? []
        isLoading = false
        persist()
    }

    private func persist() {
        guard !isLoading else { return }
        FileStorage.saveJSON(cards, to: fileName)
    }

    /// 返回元数据是否落盘成功（图片+元数据都成才算保存成功）；失败时回滚插入，不留幽灵卡
    @discardableResult
    func add(_ card: CardDesign) -> Bool {
        cards.insert(card, at: 0)
        if FileStorage.saveJSON(cards, to: fileName) {
            return true
        }
        cards.removeAll { $0.id == card.id }
        return false
    }

    func update(_ card: CardDesign) {
        if let idx = cards.firstIndex(where: { $0.id == card.id }) {
            cards[idx] = card
        }
    }

    func delete(_ card: CardDesign) {
        // 防呆：imageFile 必须是普通文件名才删文件；为空或带路径时只删元数据，
        // 绝不能让 URL 落到 cards 目录本身导致整目录被删
        let name = card.imageFile
        if !name.isEmpty && name == (name as NSString).lastPathComponent {
            let url = FileStorage.url(for: name, subdir: "cards")
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
                try? FileManager.default.removeItem(at: url)
            }
        }
        // 帧动画的逐帧图一并删（deleteFile 自带文件名安全检查，坏名自动跳过）
        for frameName in card.frameFiles {
            FileStorage.deleteFile(fileName: frameName, subdir: "frames")
        }
        // 旅程地图的头像与每个站点的照片 / 语音一并删，别在 journeys/ 里留孤儿文件
        if let journey = card.journey {
            if let head = journey.headFile {
                FileStorage.deleteFile(fileName: head, subdir: "journeys")
            }
            for stop in journey.stops {
                if let photo = stop.photoFile {
                    FileStorage.deleteFile(fileName: photo, subdir: "journeys")
                }
                if let voice = stop.voiceFile {
                    FileStorage.deleteFile(fileName: voice, subdir: "journeys")
                }
            }
        }
        NotificationManager.shared.cancelSendReminders(for: card.id)
        cards.removeAll { $0.id == card.id }
    }

    func cards(for contactID: UUID) -> [CardDesign] {
        cards.filter { $0.assignedContactID == contactID }
    }
}

final class SettingsStore: ObservableObject {
    @Published var settings: ReminderSettings = .defaults {
        didSet { persist() }
    }
    private let fileName = "settings.json"
    private var isLoading = false

    init() {
        isLoading = true
        if let saved = FileStorage.loadJSON(ReminderSettings.self, from: fileName) {
            settings = saved
        }
        isLoading = false
        persist()
    }

    private func persist() {
        guard !isLoading else { return }
        FileStorage.saveJSON(settings, to: fileName)
    }

    /// 某分组当前生效的默认卡：没设置过、或设置指向的卡片已被删除（id 查不到）都返回 nil，按未设置处理
    func groupDefaultCard(for group: ContactGroup, cardStore: CardStore) -> CardDesign? {
        guard let cardID = settings.groupDefaultCardIDs[group.rawValue] else { return nil }
        return cardStore.cards.first { $0.id == cardID }
    }

    /// 设置某分组的默认卡；传 nil = 清除设置（字典下标赋值 nil 即删键）。改 settings 触发 didSet 自动落盘
    func setGroupDefaultCard(_ cardID: UUID?, for group: ContactGroup) {
        settings.groupDefaultCardIDs[group.rawValue] = cardID
    }
}

// MARK: - 通知管理

final class NotificationManager {
    static let shared = NotificationManager()
    private let delegate = BirthdayNotificationDelegate()
    private init() {}

    var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    /// App 启动时调用一次：挂上通知代理，并注册带「已祝福，停止提醒」按钮的生日提醒分类
    func bootstrap() {
        center.delegate = delegate
        let done = UNNotificationAction(identifier: "BDAY_DONE",
                                        title: L("已祝福，停止提醒"),
                                        options: [])
        let category = UNNotificationCategory(identifier: "BIRTHDAY_NAG",
                                              actions: [done],
                                              intentIdentifiers: [],
                                              options: [])
        center.setNotificationCategories([category])
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func authorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        center.getNotificationSettings { s in
            DispatchQueue.main.async { completion(s.authorizationStatus) }
        }
    }

    /// 按当前设置，为每位联系人重排下一次生日提醒；清掉旧的 bday- 前缀请求
    func reschedule(contacts: [BContact], settings: ReminderSettings) {
        center.getPendingNotificationRequests { requests in
            let stale = requests.map { $0.identifier }.filter { $0.hasPrefix("bday-") }
            if !stale.isEmpty {
                self.center.removePendingNotificationRequests(withIdentifiers: stale)
            }
            let cal = Calendar.current
            let now = Date()
            for contact in contacts {
                guard let bday = contact.birthday,
                      let next = BirthdayCalc.nextBirthday(bday) else { continue }
                let advance = settings.effectiveAdvance(for: contact)
                guard let fireBase = cal.date(byAdding: .day, value: -advance, to: next) else { continue }
                var comps = cal.dateComponents([.year, .month, .day], from: fireBase)
                comps.hour = settings.effectiveHour(for: contact)
                comps.minute = settings.effectiveMinute(for: contact)
                comps.second = 0
                guard var fireDate = cal.date(from: comps) else { continue }
                var overduePastBirthday = false
                if fireDate <= now {
                    // 预定时刻已过、但生日还没到：顺延到下一个提醒时段补提醒，
                    // 不能整条静默丢弃（例如生日在 2 天后、提前量设了 3 天）
                    var slot = cal.dateComponents([.year, .month, .day], from: now)
                    slot.hour = settings.effectiveHour(for: contact)
                    slot.minute = settings.effectiveMinute(for: contact)
                    slot.second = 0
                    guard var slotDate = cal.date(from: slot) else { continue }
                    if slotDate <= now {
                        slotDate = cal.date(byAdding: .day, value: 1, to: slotDate) ?? slotDate
                    }
                    fireDate = slotDate
                    comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: slotDate)
                    // 例外：生日就是今天、提醒时段已过，顺延会落到生日之后——
                    // 改成立即补发（2 分钟后），不要等生日过完才响
                    if cal.startOfDay(for: slotDate) > cal.startOfDay(for: next) {
                        overduePastBirthday = true
                    }
                }

                let content = UNMutableNotificationContent()
                content.title = L("🎂 生日提醒")
                let mode = settings.effectiveMode(for: contact)
                let daysLeft = BirthdayCalc.daysUntil(bday) ?? advance
                if daysLeft == 0 {
                    content.body = String(format: L("今天是%@的生日，记得送上祝福！"), contact.name)
                } else {
                    content.body = String(format: L("还有%d天就是%@的生日（%d月%d日），提前准备一下吧。"), daysLeft, contact.name, bday.month, bday.day)
                }
                if mode == .autoSend {
                    content.body += L("（模拟自动发送：到日子会提醒你确认发送）")
                }
                content.sound = .default
                content.categoryIdentifier = "BIRTHDAY_NAG"
                content.threadIdentifier = "bday-\(contact.id.uuidString)"

                let trigger: UNNotificationTrigger = overduePastBirthday
                    ? UNTimeIntervalNotificationTrigger(timeInterval: 120, repeats: false)
                    : UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let request = UNNotificationRequest(identifier: "bday-\(contact.id.uuidString)",
                                                    content: content, trigger: trigger)
                self.center.add(request) { _ in }

                // 持续提醒：第一条之后按间隔再排一串，用通用文案（哪天发都成立），
                // 用户点开通知或点「已祝福，停止提醒」后，代理会把没发的整串取消
                if settings.nagEnabled {
                    let baseFire: Date = overduePastBirthday ? now.addingTimeInterval(120) : fireDate
                    for k in 1...ReminderSettings.nagMaxRepeats {
                        let repeatDate = baseFire.addingTimeInterval(Double(k * settings.effectiveNagInterval(for: contact)) * 3600)
                        let rContent = UNMutableNotificationContent()
                        rContent.title = content.title
                        rContent.body = String(format: L("提醒一下：%@的生日是%d月%d日，别忘了送上祝福！"),
                                               contact.name, bday.month, bday.day) + L("（再次提醒）")
                        rContent.sound = .default
                        rContent.categoryIdentifier = "BIRTHDAY_NAG"
                        rContent.threadIdentifier = "bday-\(contact.id.uuidString)"
                        let rComps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: repeatDate)
                        let rTrigger = UNCalendarNotificationTrigger(dateMatching: rComps, repeats: false)
                        let rRequest = UNNotificationRequest(identifier: "bday-\(contact.id.uuidString)-nag\(k)",
                                                             content: rContent, trigger: rTrigger)
                        self.center.add(rRequest) { _ in }
                    }
                }
            }
        }
    }

    /// 卡片库「定时发送（提醒）」：在指定时间提醒发送某张卡
    func scheduleSendReminder(card: CardDesign, contact: BContact?, at date: Date,
                              completion: @escaping (Bool) -> Void) {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let content = UNMutableNotificationContent()
        content.title = L("💌 该发送贺卡了")
        if let contact = contact {
            content.body = String(format: L("现在是给%@发送贺卡「%@」的时间。"), contact.name, card.name)
        } else {
            content.body = String(format: L("现在是发送贺卡「%@」的时间。"), card.name)
        }
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let id = "send-\(card.id.uuidString)-\(Int(date.timeIntervalSince1970))"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request) { error in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }

    /// 取消某张卡的全部「定时发送」提醒（删卡时调用，避免卡没了提醒还弹）
    func cancelSendReminders(for cardID: UUID) {
        center.getPendingNotificationRequests { requests in
            let prefix = "send-\(cardID.uuidString)"
            let ids = requests.map { $0.identifier }.filter { $0.hasPrefix(prefix) }
            if !ids.isEmpty {
                self.center.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
    }
}

extension Notification.Name {
    /// Batch 1：点开某条生日通知后，首页要直接打开那位联系人的详情页（提醒中心在最上面）
    static let openBirthdayContact = Notification.Name("BDReminderOpenBirthdayContact")
}

/// 通知代理：App 在前台时生日提醒也弹横幅；用户点开某条生日通知、
/// 或点通知上的「已祝福，停止提醒」后，取消这位联系人还没发的后续重复提醒，
/// 并清掉通知中心里已送达的同串提醒，避免堆一排
private final class BirthdayNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.identifier
        if id.hasPrefix("bday-") {
            // 标识形如 bday-<UUID> 或 bday-<UUID>-nag<k>，截出这位联系人的整串基名
            var base = id
            if let range = base.range(of: "-nag") {
                base = String(base[..<range.lowerBound])
            }
            center.getPendingNotificationRequests { requests in
                let ids = requests.map { $0.identifier }.filter { $0 == base || $0.hasPrefix(base + "-nag") }
                if !ids.isEmpty {
                    center.removePendingNotificationRequests(withIdentifiers: ids)
                }
            }
            center.getDeliveredNotifications { delivered in
                let ids = delivered.map { $0.request.identifier }.filter { $0 == base || $0.hasPrefix(base + "-nag") }
                if !ids.isEmpty {
                    center.removeDeliveredNotifications(withIdentifiers: ids)
                }
            }
            // Batch 1：只有点开通知本身（不是点「已祝福，停止提醒」）才打开详情页；
            // 首页收到后直接推到那位联系人的详情页，提醒中心在最上面
            if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                let uuidString = String(base.dropFirst("bday-".count))
                if UUID(uuidString: uuidString) != nil {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .openBirthdayContact, object: uuidString)
                    }
                }
            }
        }
        completionHandler()
    }
}

// MARK: - 日历管理（EventKit）

final class CalendarManager {
    static let shared = CalendarManager()
    private let store = EKEventStore()
    private init() {}

    private enum AddOutcome {
        case added, alreadyExists, failed
    }

    /// 已拿到授权的前提下建事件（同步执行，调用方负责串行）；同名同窗口事件视为已存在
    private func createEventIfNeeded(for contact: BContact) -> AddOutcome {
        guard let bday = contact.birthday,
              let next = BirthdayCalc.nextBirthday(bday) else { return .failed }
        let title = "🎂 \(contact.name)的生日"
        let cal = Calendar.current
        // 去重：查下一次生日前后窗口内有没有同名事件
        let from = cal.date(byAdding: .day, value: -1, to: next) ?? next
        let to = cal.date(byAdding: .day, value: 2, to: next) ?? next
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        if store.events(matching: predicate).contains(where: { $0.title == title }) {
            return .alreadyExists
        }
        let event = EKEvent(eventStore: store)
        event.title = title
        var startComps = cal.dateComponents([.year, .month, .day], from: next)
        startComps.hour = 9
        startComps.minute = 0
        event.startDate = cal.date(from: startComps)
        event.endDate = cal.date(byAdding: .hour, value: 1, to: event.startDate)
        event.calendar = store.defaultCalendarForNewEvents
        event.recurrenceRules = [EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)]
        do {
            try store.save(event, span: .thisEvent)
            return .added
        } catch {
            return .failed
        }
    }

    /// 把一位联系人的生日加进系统日历（每年重复）；已存在同名事件则跳过
    func addBirthdayEvent(for contact: BContact, completion: @escaping (String) -> Void) {
        guard contact.birthday != nil else {
            completion(String(format: L("%@还没有填写生日。"), contact.name))
            return
        }
        store.requestFullAccessToEvents { granted, _ in
            guard granted else {
                DispatchQueue.main.async { completion(L("没有获得日历权限，请在系统设置里允许。")) }
                return
            }
            let title = "🎂 \(contact.name)的生日"
            let outcome = self.createEventIfNeeded(for: contact)
            DispatchQueue.main.async {
                switch outcome {
                case .added:
                    completion(String(format: L("已把「%@」加进系统日历，每年重复。"), title))
                case .alreadyExists:
                    completion(String(format: L("「%@」已经在日历里了，没有重复添加。"), title))
                case .failed:
                    completion(L("保存到日历失败，请再试一次。"))
                }
            }
        }
    }

    /// 一键全部加入：只请求一次授权，然后串行逐个建（避免并发查-存竞态与计数竞争）
    func addAllBirthdays(contacts: [BContact], completion: @escaping (String) -> Void) {
        let targets = contacts.filter { $0.birthday != nil }
        guard !targets.isEmpty else {
            completion(L("还没有带生日的联系人。"))
            return
        }
        store.requestFullAccessToEvents { granted, _ in
            guard granted else {
                DispatchQueue.main.async { completion(L("没有获得日历权限，请在系统设置里允许。")) }
                return
            }
            var added = 0
            var skipped = 0
            var failed = 0
            for contact in targets {
                switch self.createEventIfNeeded(for: contact) {
                case .added: added += 1
                case .alreadyExists: skipped += 1
                case .failed: failed += 1
                }
            }
            DispatchQueue.main.async {
                var msg = String(format: L("已处理 %d 位联系人：新加 %d 位"), targets.count, added)
                if skipped > 0 { msg += String(format: L("，已在日历里跳过 %d 位"), skipped) }
                if failed > 0 { msg += String(format: L("，失败 %d 位"), failed) }
                msg += L("。")
                completion(msg)
            }
        }
    }
}

// MARK: - 通讯录导入

enum ContactsImporter {
    static func importContacts(into store: ContactStore,
                               completion: @escaping (String) -> Void) {
        let cnStore = CNContactStore()
        cnStore.requestAccess(for: .contacts) { granted, _ in
            guard granted else {
                DispatchQueue.main.async {
                    completion(L("没有获得通讯录权限。可以在系统设置里允许，或手动添加联系人。"))
                }
                return
            }
            let keys: [CNKeyDescriptor] = [
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactBirthdayKey as CNKeyDescriptor,
                CNContactEmailAddressesKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
            ]
            let request = CNContactFetchRequest(keysToFetch: keys)
            // 判重：规范化姓名（去空格、转小写）做键；已有联系人 + 本批已导入的一起算，
            // 通讯录内部同名也不会重复进来
            func nameKey(_ s: String) -> String {
                s.replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: "　", with: "")
                    .lowercased()
            }
            var seen = Set(store.contacts.map { nameKey($0.name) })
            var imported = 0
            var skipped = 0
            var fetched: [BContact] = []
            do {
                try cnStore.enumerateContacts(with: request) { cn, _ in
                    // 用系统姓名格式器：中文"姓+名"、英文"名 姓"，顺序与空格都按系统习惯
                    var displayName = CNContactFormatter.string(from: cn, style: .fullName) ?? ""
                    if displayName.isEmpty {
                        displayName = (cn.familyName + cn.givenName).trimmingCharacters(in: .whitespaces)
                    }
                    guard !displayName.isEmpty else { return }
                    let key = nameKey(displayName)
                    if seen.contains(key) {
                        skipped += 1
                        return
                    }
                    seen.insert(key)
                    var bday: BirthdayDate? = nil
                    if let comps = cn.birthday {
                        bday = BirthdayDate(year: comps.year, month: comps.month ?? 1, day: comps.day ?? 1)
                    }
                    let email = (cn.emailAddresses.first?.value as? String) ?? ""
                    let phone = cn.phoneNumbers.first?.value.stringValue ?? ""
                    fetched.append(BContact(name: displayName, birthday: bday,
                                            email: email, phone: phone))
                    imported += 1
                }
            } catch {
                DispatchQueue.main.async { completion(String(format: L("读取通讯录失败：%@"), error.localizedDescription)) }
                return
            }
            DispatchQueue.main.async {
                store.addBatch(fetched)
                completion(String(format: L("导入完成：新增 %d 位，跳过重名 %d 位。没有生日的联系人在「待补生日」里。"), imported, skipped))
            }
        }
    }
}

// MARK: - 首页

struct HomeView: View {
    @EnvironmentObject var contactStore: ContactStore
    @EnvironmentObject var cardStore: CardStore
    @EnvironmentObject var settingsStore: SettingsStore
    /// Batch 1：通知深链用——点开生日通知时，这里直接推到那位联系人的详情页
    @State private var navPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navPath) {
            Group {
                if contactStore.upcomingSorted.isEmpty {
                    ContentUnavailableView(L("还没有带生日的联系人"),
                                           systemImage: "calendar.badge.plus",
                                           description: Text(L("去「联系人」添加或从通讯录导入吧。")))
                } else {
                    List {
                        ForEach(Array(contactStore.upcomingSorted.enumerated()), id: \.element.id) { index, contact in
                            NavigationLink(value: contact.id) {
                                if index == 0 {
                                    // 最近的一个生日 = 首页主角：白卡坐黄场上，另加一枚「最近」黄徽标点名
                                    HStack(alignment: .top, spacing: 8) {
                                        UpcomingRow(contact: contact)
                                        Text(L("最近"))
                                            .font(.caption2).bold()
                                            .foregroundStyle(AppTheme.ink)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Capsule().fill(AppTheme.sunny))
                                            .overlay(Capsule().stroke(AppTheme.ink, lineWidth: 1.5))
                                    }
                                    .padding(10)
                                    .modifier(ChunkyCard(fill: AppTheme.paper))
                                } else {
                                    UpcomingRow(contact: contact)
                                        .chunkyRow()
                                }
                            }
                            .listRowSeparator(index == 0 ? .hidden : .automatic)
                        }
                    }
                    .sunnyScreen()
                    .navigationDestination(for: UUID.self) { id in
                        ContactDetailView(contactID: id)
                    }
                }
            }
            .background(AppTheme.sunny)
            .navigationTitle(L("🎂 即将到来的生日"))
            .toolbarBackground(AppTheme.sunny, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .onAppear {
                reconcileAssignments()
                NotificationManager.shared.reschedule(contacts: contactStore.contacts,
                                                      settings: settingsStore.settings)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openBirthdayContact)) { note in
                // Batch 1：点开生日通知——只打开还存在的联系人，推到 TA 的详情页（提醒中心在最上面）
                if let uuidString = note.object as? String,
                   let id = UUID(uuidString: uuidString),
                   contactStore.contact(id: id) != nil {
                    navPath.append(id)
                }
            }
        }
    }

    /// 归属对账：卡片指向已删除联系人时清掉归属；每个联系人的卡片池以卡片上的
    /// assignedContactID 为准重建，保证两处记录不分叉
    private func reconcileAssignments() {
        let validIDs = Set(contactStore.contacts.map { $0.id })
        for card in cardStore.cards {
            if let owner = card.assignedContactID, !validIDs.contains(owner) {
                var fixed = card
                fixed.assignedContactID = nil
                cardStore.update(fixed)
            }
        }
        for contact in contactStore.contacts {
            let pool = cardStore.cards(for: contact.id).map { $0.id }
            if pool != contact.cardPoolIDs {
                var fixed = contact
                fixed.cardPoolIDs = pool
                contactStore.update(fixed)
            }
        }
    }
}

struct UpcomingRow: View {
    let contact: BContact

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(contact.name).font(.headline)
                    if contact.isStarred {
                        Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
                    }
                    Text(L(contact.group.rawValue))
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
                if let b = contact.birthday {
                    Text(b.displayText).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let b = contact.birthday, let days = BirthdayCalc.daysUntil(b) {
                VStack(alignment: .trailing, spacing: 2) {
                    if days == 0 {
                        Text(L("就是今天！")).font(.headline).foregroundStyle(.pink)
                    } else {
                        Text(String(format: L("还有 %d 天"), days)).font(.headline)
                    }
                    if let age = BirthdayCalc.turningAge(b) {
                        Text(String(format: L("将满 %d 岁"), age)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 联系人列表

/// 联系人列表的两种分类方式：按字母 / 按分组（@AppStorage 持久化）。
enum ContactsViewMode: String, CaseIterable, Identifiable {
    case alphabetical = "按字母"
    case group = "按分组"
    var id: String { rawValue }
}

/// 联系人列表：iPhone 通讯录式简洁白底列表（本页不用黄底 chunky 卡片风）。
/// 顶部一段式切换（不随列表滚动），两种分类共用同一种 plain 白底行。
struct ContactListView: View {
    @EnvironmentObject var contactStore: ContactStore
    @EnvironmentObject var cardStore: CardStore
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var searchText = ""
    @State private var showingAdd = false
    @State private var importMessage: String? = nil
    @AppStorage("bdreminder.contactsViewMode") private var viewMode: ContactsViewMode = .alphabetical

    private var filtered: [BContact] {
        if searchText.isEmpty { return contactStore.contacts }
        return contactStore.contacts.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.note.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// 名字首字母（拉丁化后取首字母；无 A–Z 首字母归 "#"）
    private func firstLetter(of name: String) -> String {
        let latin = name.applyingTransform(.toLatin, reverse: false) ?? name
        let folded = latin.folding(options: .diacriticInsensitive, locale: .current)
        guard let first = folded.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "#" }
        let letter = String(first).uppercased()
        if ("A"..."Z").contains(letter) { return letter }
        return "#"
    }

    /// 按字母分组：A–Z 排序，"#" 排最后；组内按名字排序
    private var alphabeticalSections: [(letter: String, contacts: [BContact])] {
        let grouped = Dictionary(grouping: filtered) { firstLetter(of: $0.name) }
        let letters = grouped.keys.sorted {
            if $0 == "#" { return false }
            if $1 == "#" { return true }
            return $0 < $1
        }
        return letters.map { letter in
            (letter: letter, contacts: grouped[letter]!.sorted { $0.name < $1.name })
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $viewMode) {
                    ForEach(ContactsViewMode.allCases) { mode in
                        Text(L(mode.rawValue)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))

                ScrollViewReader { proxy in
                    ZStack(alignment: .trailing) {
                        List {
                            if !contactStore.withoutBirthday.isEmpty && searchText.isEmpty {
                                Section(L("待补生日（点进去补上生日）")) {
                                    ForEach(contactStore.withoutBirthday) { contact in
                                        NavigationLink {
                                            ContactDetailView(contactID: contact.id)
                                        } label: {
                                            Label(contact.name, systemImage: "calendar.badge.exclamationmark")
                                        }
                                    }
                                }
                            }
                            if viewMode == .alphabetical {
                                ForEach(alphabeticalSections, id: \.letter) { section in
                                    Section(section.letter) {
                                        ForEach(section.contacts) { contact in
                                            NavigationLink {
                                                ContactDetailView(contactID: contact.id)
                                            } label: {
                                                ContactRow(contact: contact)
                                            }
                                        }
                                    }
                                    .id("letter-\(section.letter)")
                                }
                            } else {
                                ForEach(ContactGroup.allCases) { group in
                                    let members = filtered.filter { $0.group == group }
                                    if !members.isEmpty {
                                        Section(L(group.rawValue)) {
                                            // 分组管理入口：已选人数按全组（未过滤）统计
                                            let allMembers = contactStore.contacts.filter { $0.group == group }
                                            let selectedCount = allMembers.filter { $0.receivesGroupCard }.count
                                            NavigationLink {
                                                GroupDetailView(group: group)
                                            } label: {
                                                HStack {
                                                    Label(L("管理本组"), systemImage: "person.3")
                                                    Spacer()
                                                    Text(String(format: L("已选 %d/%d 人"), selectedCount, allMembers.count))
                                                        .font(.caption).foregroundStyle(.secondary)
                                                }
                                            }
                                            ForEach(members) { contact in
                                                NavigationLink {
                                                    ContactDetailView(contactID: contact.id)
                                                } label: {
                                                    ContactRow(contact: contact)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .background(Color(.systemBackground))

                        // 右侧 A–Z 快速索引：只在按字母模式且多于一个分区时出现
                        if viewMode == .alphabetical && alphabeticalSections.count > 1 {
                            VStack(spacing: 1) {
                                ForEach(alphabeticalSections.map(\.letter), id: \.self) { letter in
                                    Button(letter) {
                                        withAnimation {
                                            proxy.scrollTo("letter-\(letter)", anchor: .top)
                                        }
                                    }
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color(.systemGray))
                                    .frame(width: 22, height: 16)
                                }
                            }
                            .padding(.trailing, 2)
                        }
                    }
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle(L("联系人"))
            .searchable(text: $searchText, prompt: Text(L("搜索姓名或备注")))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        ContactsImporter.importContacts(into: contactStore) { msg in
                            importMessage = msg
                            NotificationManager.shared.reschedule(contacts: contactStore.contacts,
                                                                  settings: settingsStore.settings)
                        }
                    } label: {
                        Label(L("从通讯录导入"), systemImage: "person.crop.circle.badge.plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: {
                        Label(L("添加"), systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                ContactFormView(contact: nil)
            }
            .alert(L("通讯录导入"), isPresented: Binding(
                get: { importMessage != nil },
                set: { if !$0 { importMessage = nil } }
            )) {
                Button(L("好")) { importMessage = nil }
            } message: {
                Text(importMessage ?? "")
            }
        }
    }
}

// MARK: - 分组默认卡选择

/// 给某个分组挑一张默认卡：列出卡片库全部卡片，点一张即设为该组默认并关闭；
/// 「不设置」清除当前设置。设置指向的卡被删掉时，列表行与详情页都按未设置处理（见 SettingsStore.groupDefaultCard）。
struct GroupDefaultCardPickerView: View {
    @EnvironmentObject var cardStore: CardStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    let group: ContactGroup

    var body: some View {
        NavigationStack {
            Group {
                if cardStore.cards.isEmpty {
                    ContentUnavailableView(L("卡片库还是空的，先去做一张卡。"),
                                           systemImage: "rectangle.stack.badge.plus")
                } else {
                    List {
                        Section {
                            Button(L("不设置")) {
                                settingsStore.setGroupDefaultCard(nil, for: group)
                                dismiss()
                            }
                        }
                        .chunkyRow()
                        Section {
                            ForEach(cardStore.cards) { card in
                                Button {
                                    settingsStore.setGroupDefaultCard(card.id, for: group)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 10) {
                                        if let img = FileStorage.loadImage(fileName: card.imageFile, subdir: "cards") {
                                            Image(uiImage: img)
                                                .resizable().scaledToFill()
                                                .frame(width: 36, height: 48)
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                        } else {
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color.secondary.opacity(0.2))
                                                .frame(width: 36, height: 48)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(card.name)
                                                .foregroundStyle(.primary)
                                            Text(card.createdAt.formatted(date: .abbreviated, time: .omitted))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if settingsStore.settings.groupDefaultCardIDs[group.rawValue] == card.id {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                }
                            }
                        }
                        .chunkyRow()
                    }
                    .sunnyScreen()
                    .toolbarBackground(AppTheme.sunny, for: .navigationBar)
                    .toolbarBackgroundVisibility(.visible, for: .navigationBar)
                }
            }
            .navigationTitle(String(format: L("分组默认卡 · %@"), L(group.rawValue)))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("取消")) { dismiss() }
                }
            }
        }
    }
}

// MARK: - 分组管理

/// 分组管理页：给本组选默认卡 + 勾选谁接收这张卡（opt-in，默认谁都不勾——只有被选中的人才发）。
/// 勾选状态存在 BContact.receivesGroupCard；联系人详情页的分组默认卡回退也只对被勾选的人生效。
struct GroupDetailView: View {
    @EnvironmentObject var contactStore: ContactStore
    @EnvironmentObject var cardStore: CardStore
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var showingPicker = false

    let group: ContactGroup

    /// 与联系人列表同序：store 顺序按本组过滤
    private var members: [BContact] {
        contactStore.contacts.filter { $0.group == group }
    }

    private var selectedCount: Int {
        members.filter { $0.receivesGroupCard }.count
    }

    private var defaultCard: CardDesign? {
        settingsStore.groupDefaultCard(for: group, cardStore: cardStore)
    }

    var body: some View {
        List {
            Section {
                Button {
                    showingPicker = true
                } label: {
                    HStack(spacing: 10) {
                        if let card = defaultCard {
                            if let img = FileStorage.loadImage(fileName: card.imageFile, subdir: "cards") {
                                Image(uiImage: img)
                                    .resizable().scaledToFill()
                                    .frame(width: 27, height: 36)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                            Text(card.name)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        } else {
                            Text(L("未设置"))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            } header: {
                Text(L("分组默认卡"))
                    .foregroundStyle(AppTheme.ink)
            } footer: {
                if defaultCard != nil {
                    Text(String(format: L("已选 %d / %d 人会收到这张卡"), selectedCount, members.count))
                } else {
                    Text(L("先给这个分组选一张默认卡"))
                }
            }
            .chunkyRow()

            Section {
                if members.isEmpty {
                    Text(L("这个分组还没有联系人。"))
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Button(L("全选")) { setAll(true) }
                        Spacer()
                        Button(L("全不选")) { setAll(false) }
                    }
                    ForEach(members) { contact in
                        Button {
                            toggle(contact)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: contact.receivesGroupCard ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(contact.receivesGroupCard ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(contact.name)
                                        .foregroundStyle(.primary)
                                    Text(contact.birthday?.displayText ?? "—")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !cardStore.cards(for: contact.id).isEmpty {
                                    Text(L("已备自己的卡"))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .chunkyRow()
        }
        .sunnyScreen()
        .toolbarBackground(AppTheme.sunny, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .navigationTitle(L(group.rawValue))
        .sheet(isPresented: $showingPicker) {
            GroupDefaultCardPickerView(group: group)
        }
    }

    private func toggle(_ contact: BContact) {
        var updated = contact
        updated.receivesGroupCard.toggle()
        contactStore.update(updated)
    }

    private func setAll(_ value: Bool) {
        for member in members where member.receivesGroupCard != value {
            var updated = member
            updated.receivesGroupCard = value
            contactStore.update(updated)
        }
    }
}

struct ContactRow: View {
    let contact: BContact

    /// 头像缩写：中文名取首字；拉丁名取前两个词首字母（大写）
    private var initials: String {
        let name = contact.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = name.first else { return "?" }
        let words = name.split(separator: " ")
        if words.count >= 2, first.isASCII, first.isLetter {
            let a = words[0].first.map(String.init) ?? ""
            let b = words[1].first.map(String.init) ?? ""
            return (a + b).uppercased()
        }
        return String(first)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 36, height: 36)
                Text(initials)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(.darkGray))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(contact.name)
                    if contact.isStarred {
                        Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption2)
                    }
                }
                if let b = contact.birthday {
                    Text(b.displayText).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(L("未填生日")).font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            if let b = contact.birthday, let days = BirthdayCalc.daysUntil(b) {
                Text(days == 0 ? L("今天") : String(format: L("%d 天后"), days))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 语音笔记（联系人「关于 TA」）

/// 录音 / 播放 / 转写引擎：只管音频与状态，界面与落盘由 VoiceNoteSectionView 和调用方处理。
/// 录音存 Documents/voice/<UUID>.m4a；转写走系统 SFSpeechRecognizer（优先中文、尽量本机
/// 识别），转写结果只通过回调送回界面追加进笔记草稿——录音文件才是正本，转写失败不影响
/// 已保存的录音。所有授权都在流程内请求，失败只给中文提示，不崩溃。
final class VoiceNoteEngine: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isPlaying = false
    @Published private(set) var isTranscribing = false
    @Published var statusText: String? = nil

    /// 录音停止并落盘后回调（参数为新文件名）
    var onRecordingSaved: ((String) -> Void)?
    /// 转写成功后回调（参数为转写文字，由界面决定如何追加，这里不直接改笔记）
    var onTranscriptReady: ((String) -> Void)?

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var recordingFileName: String?

    // 录音

    func toggleRecording() {
        if isRecording {
            stopRecording(save: true)
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            beginRecording()
        case .denied:
            statusText = L("没有麦克风权限，请到系统「设置」里允许使用麦克风；也可以直接在下面打字记笔记。")
        case .undetermined:
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.beginRecording()
                    } else {
                        self?.statusText = L("没有麦克风权限，无法录音；可以直接在下面打字记笔记。")
                    }
                }
            }
        @unknown default:
            statusText = L("麦克风权限状态未知，暂时无法录音。")
        }
    }

    private func beginRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let name = "\(UUID().uuidString).m4a"
            let url = FileStorage.url(for: name, subdir: "voice")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let rec = try AVAudioRecorder(url: url, settings: settings)
            guard rec.record() else {
                FileStorage.deleteFile(fileName: name, subdir: "voice")
                statusText = L("录音启动失败，请再试一次。")
                return
            }
            recorder = rec
            recordingFileName = name
            isRecording = true
            statusText = nil
        } catch {
            statusText = String(format: L("录音启动失败：%@"), error.localizedDescription)
        }
    }

    private func stopRecording(save: Bool) {
        guard let rec = recorder else { return }
        rec.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let name = recordingFileName else { return }
        recordingFileName = nil
        if save {
            onRecordingSaved?(name)
            transcribe(fileName: name)
        } else {
            // 半截录音（界面中途消失）直接丢弃，不落盘回调、不留孤儿文件
            FileStorage.deleteFile(fileName: name, subdir: "voice")
        }
    }

    // 播放

    func togglePlayback(fileName: String) {
        if isPlaying {
            stopPlayback()
            return
        }
        let url = FileStorage.url(for: fileName, subdir: "voice")
        guard FileManager.default.fileExists(atPath: url.path) else {
            statusText = L("录音文件找不到了，可能已被删除。")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.play()
            player = p
            isPlaying = true
            statusText = nil
        } catch {
            statusText = String(format: L("播放失败：%@"), error.localizedDescription)
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    /// 界面消失时收尾：正在录的半截丢弃，播放停掉
    func stopAll() {
        if isRecording { stopRecording(save: false) }
        stopPlayback()
    }

    // 转写

    private func transcribe(fileName: String) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if status == .authorized {
                    self.runTranscription(fileName: fileName)
                } else {
                    self.statusText = L("未获得语音识别授权，录音已保存；可以在下面手动打字。")
                }
            }
        }
    }

    private func runTranscription(fileName: String) {
        let recognizer: SFSpeechRecognizer?
        if let zh = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")), zh.isAvailable {
            recognizer = zh
        } else if let en = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), en.isAvailable {
            recognizer = en
        } else {
            recognizer = nil
        }
        guard let recognizer = recognizer else {
            statusText = L("转写失败，录音已保存。")
            return
        }
        isTranscribing = true
        let request = SFSpeechURLRecognitionRequest(url: FileStorage.url(for: fileName, subdir: "voice"))
        // 尽量本机识别（识别器支持才开）；文件请求关掉中间结果，只等最终稿
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.shouldReportPartialResults = false
        recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let result = result, result.isFinal {
                    self.isTranscribing = false
                    let text = result.bestTranscription.formattedString
                    if text.isEmpty {
                        self.statusText = L("转写失败，录音已保存。")
                    } else {
                        self.statusText = nil
                        self.onTranscriptReady?(text)
                    }
                } else if error != nil {
                    self.isTranscribing = false
                    self.statusText = L("转写失败，录音已保存。")
                }
            }
        }
    }
}

extension VoiceNoteEngine: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.player = nil
            self?.isPlaying = false
        }
    }
}

/// 「关于 TA」区块（录音 + 播放 + 笔记 + 引导问答），联系人表单与详情页共用。
/// 录音文件的生命周期有两种口径，由调用方决定：
/// - 不给 onRetireFile（详情页，改动即时生效）：录音被替换/删除时立刻删旧文件。
/// - 给 onRetireFile（表单，保存才生效）：被替换/删除的文件名先报给调用方，
///   由调用方在保存时统一删除、取消时只删本次新建的录音，保证取消能恢复原状。
struct VoiceNoteSectionView: View {
    @Binding var voiceNoteFile: String?
    @Binding var noteText: String
    var onRetireFile: ((String) -> Void)? = nil
    var onNewRecording: ((String) -> Void)? = nil

    @StateObject private var engine = VoiceNoteEngine()
    @State private var showingGuide = false

    var body: some View {
        Group {
            if engine.isRecording {
                Button(role: .destructive) {
                    engine.toggleRecording()
                } label: {
                    Label(L("停止录音"), systemImage: "stop.circle.fill")
                }
                Text(L("正在录音……说说你对 TA 的想法吧，点「停止录音」结束。"))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Button {
                    engine.toggleRecording()
                } label: {
                    Label(voiceNoteFile == nil ? L("开始录音") : L("重录（会替换现在的录音）"),
                          systemImage: "mic.circle")
                }
            }

            if voiceNoteFile != nil && !engine.isRecording {
                Button {
                    if let name = voiceNoteFile { engine.togglePlayback(fileName: name) }
                } label: {
                    Label(engine.isPlaying ? L("停止播放") : L("播放录音"),
                          systemImage: engine.isPlaying ? "stop.circle" : "play.circle")
                }
                Button(role: .destructive) {
                    deleteRecording()
                } label: {
                    Label(L("删除录音"), systemImage: "trash")
                }
            }

            if engine.isTranscribing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(L("正在把录音转成文字……"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let status = engine.statusText {
                Text(status).font(.caption).foregroundStyle(.orange)
            }

            TextEditor(text: $noteText)
                .frame(minHeight: 90)
            Text(L("这是笔记，可以直接打字写；录音转写出来的文字会自动追加到末尾，不会盖掉已经写好的内容。"))
                .font(.caption).foregroundStyle(.secondary)

            Button {
                showingGuide = true
            } label: {
                Label(L("回答几个小问题，帮我想想"), systemImage: "text.bubble")
            }
        }
        .onAppear {
            engine.onRecordingSaved = { name in
                if let old = voiceNoteFile, old != name {
                    retire(old)
                }
                onNewRecording?(name)
                voiceNoteFile = name
            }
            engine.onTranscriptReady = { text in
                appendToNote(text)
            }
        }
        .onDisappear { engine.stopAll() }
        .sheet(isPresented: $showingGuide) {
            VoiceNoteGuideView(noteText: $noteText)
        }
    }

    private func retire(_ fileName: String) {
        if let onRetireFile = onRetireFile {
            onRetireFile(fileName)
        } else {
            FileStorage.deleteFile(fileName: fileName, subdir: "voice")
        }
    }

    private func deleteRecording() {
        engine.stopPlayback()
        guard let name = voiceNoteFile else { return }
        retire(name)
        voiceNoteFile = nil
    }

    /// 转写文字只追加、不覆盖：草稿为空直接放入，否则换行接在末尾
    private func appendToNote(_ text: String) {
        if noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            noteText = text
        } else if noteText.hasSuffix("\n") {
            noteText += text
        } else {
            noteText += "\n" + text
        }
    }
}

/// 引导问答：一次一个问题、共 4 问，每问可跳过；
/// 完成时把已回答的问答以「问：…／答：…」格式追加进笔记草稿（不覆盖已有内容）
struct VoiceNoteGuideView: View {
    @Binding var noteText: String
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var answers: [String] = ["", "", "", ""]

    static var questions: [String] {
        [L("你们怎么认识的？"),
         L("为什么 TA 对你重要？"),
         L("TA 喜欢什么？"),
         L("还有什么想记住的？")]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(format: L("第 %d / %d 问"), step + 1, Self.questions.count)) {
                    Text(Self.questions[step]).font(.headline)
                    TextEditor(text: $answers[step])
                        .frame(minHeight: 100)
                        .id(step)
                    Text(L("想不到可以跳过，这一问不填也没关系。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L("关于 TA"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("取消")) { cancel() }
                }
                ToolbarItem(placement: .bottomBar) {
                    if step < Self.questions.count - 1 {
                        Button(L("跳过这一问")) { step += 1 }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if step < Self.questions.count - 1 {
                        Button(L("下一问")) { step += 1 }
                    } else {
                        Button(L("完成")) { finish() }
                    }
                }
            }
        }
    }

    private func cancel() {
        // 取消：什么都不合并，直接关掉（答案都还是本页的临时状态）
        dismiss()
    }

    private func finish() {
        var blocks: [String] = []
        for (i, q) in Self.questions.enumerated() {
            let a = answers[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if !a.isEmpty {
                blocks.append(String(format: L("问：%@\n答：%@"), q, a))
            }
        }
        if !blocks.isEmpty {
            let block = blocks.joined(separator: "\n")
            if noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                noteText = block
            } else if noteText.hasSuffix("\n") {
                noteText += block
            } else {
                noteText += "\n" + block
            }
        }
        dismiss()
    }
}

// MARK: - 联系人详情

struct ContactDetailView: View {
    @EnvironmentObject var contactStore: ContactStore
    @EnvironmentObject var cardStore: CardStore
    @EnvironmentObject var settingsStore: SettingsStore
    let contactID: UUID
    @State private var showingEdit = false
    @State private var showingMaker = false
    @State private var calendarMessage: String? = nil
    @Environment(\.dismiss) private var dismiss

    private var contact: BContact? {
        contactStore.contact(id: contactID)
    }

    /// 「关于 TA」区块在详情页的改动即时生效：绑定直接写穿到 store
    private func voiceFileBinding(for contact: BContact) -> Binding<String?> {
        Binding(
            get: { contact.voiceNoteFile },
            set: { newValue in
                var updated = contact
                updated.voiceNoteFile = newValue
                contactStore.update(updated)
            }
        )
    }

    private func noteTextBinding(for contact: BContact) -> Binding<String> {
        Binding(
            get: { contact.noteText ?? "" },
            set: { newValue in
                var updated = contact
                updated.noteText = newValue.isEmpty ? nil : newValue
                contactStore.update(updated)
            }
        )
    }

    /// 电话类 URL（tel:/sms:）：只留数字与开头的 +，其余字符（空格、括号、横杠）全部去掉；
    /// 清洗后没有数字就返回 nil，按钮不显示
    private func phoneURL(_ raw: String, scheme: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.filter { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return URL(string: "\(scheme):\(trimmed.hasPrefix("+") ? "+" : "")\(digits)")
    }

    /// Batch 1：改了本人的提醒设置就重排 TA 的生日提醒（全局设置页改完也会重排，两处一致）
    private func rescheduleForContact() {
        NotificationManager.shared.reschedule(contacts: contactStore.contacts,
                                              settings: settingsStore.settings)
    }

    /// Batch 1 提醒中心要发的那张卡：先拿 TA 卡片池里的第一张；没有就拿分组默认卡
    /// （只在分组管理页被勾选接收时才拿）；两处都没有就返回 nil，提醒中心改成「去做一张卡」
    private func hubCard(for contact: BContact) -> CardDesign? {
        if let first = cardStore.cards(for: contact.id).first { return first }
        if contact.receivesGroupCard {
            return settingsStore.groupDefaultCard(for: contact.group, cardStore: cardStore)
        }
        return nil
    }

    /// Batch 1：发短信/发卡时预填的祝福语——今年那行写了就用它，没写就用「生日快乐！」
    private func hubBlessing(for contact: BContact) -> String {
        let note = (contact.thisYearNote ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return note.isEmpty ? L("生日快乐！") : note
    }

    /// Batch 1：发短信链接，body 里预填今年的祝福语；没电话就返回 nil，按钮不显示
    private func smsURL(for contact: BContact) -> URL? {
        guard let base = phoneURL(contact.phone, scheme: "sms") else { return nil }
        guard let encoded = hubBlessing(for: contact)
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return base }
        return URL(string: "\(base.absoluteString)&body=\(encoded)")
    }

    /// Batch 1：今年那行——改动即时写穿到 store（不重排提醒，文字不影响排期）
    private func thisYearNoteBinding(for contact: BContact) -> Binding<String> {
        Binding(
            get: { contact.thisYearNote ?? "" },
            set: { newValue in
                var updated = contact
                updated.thisYearNote = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newValue
                contactStore.update(updated)
            }
        )
    }

    /// Batch 1：本人提前天数覆盖（nil = 跟随全局：普通按全局、星标按星标全局值）
    private func reminderAdvanceBinding(for contact: BContact) -> Binding<Int?> {
        Binding(
            get: { contact.reminderAdvanceDays },
            set: { newValue in
                var updated = contact
                updated.reminderAdvanceDays = newValue
                contactStore.update(updated)
                rescheduleForContact()
            }
        )
    }

    /// Batch 1：本人提醒时间覆盖（读出来是生效值，改了就写成本人覆盖）
    private func reminderTimeBinding(for contact: BContact) -> Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = settingsStore.settings.effectiveHour(for: contact)
                comps.minute = settingsStore.settings.effectiveMinute(for: contact)
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                var updated = contact
                updated.reminderHour = comps.hour ?? 9
                updated.reminderMinute = comps.minute ?? 0
                contactStore.update(updated)
                rescheduleForContact()
            }
        )
    }

    /// Batch 1：本人发送方式覆盖（nil = 跟随分组）
    private func reminderModeBinding(for contact: BContact) -> Binding<SendMode?> {
        Binding(
            get: { contact.sendModeRaw.flatMap { SendMode(rawValue: $0) } },
            set: { newValue in
                var updated = contact
                updated.sendModeRaw = newValue?.rawValue
                contactStore.update(updated)
                rescheduleForContact()
            }
        )
    }

    /// Batch 1：本人重复提醒间隔覆盖（nil = 跟随全局）
    private func reminderNagBinding(for contact: BContact) -> Binding<Int?> {
        Binding(
            get: { contact.nagIntervalHours },
            set: { newValue in
                var updated = contact
                updated.nagIntervalHours = newValue
                contactStore.update(updated)
                rescheduleForContact()
            }
        )
    }

    /// Batch 1：这个人有没有设过任何本人覆盖（有才显示「恢复跟随全局设置」）
    private func hasReminderOverride(for contact: BContact) -> Bool {
        contact.reminderAdvanceDays != nil || contact.reminderHour != nil
            || contact.reminderMinute != nil || contact.sendModeRaw != nil
            || contact.nagIntervalHours != nil
    }

    /// Batch 1：清掉这个人的全部提醒覆盖，回到全局/分组设置，并重排提醒
    private func clearReminderOverrides(for contact: BContact) {
        var updated = contact
        updated.reminderAdvanceDays = nil
        updated.reminderHour = nil
        updated.reminderMinute = nil
        updated.sendModeRaw = nil
        updated.nagIntervalHours = nil
        contactStore.update(updated)
        rescheduleForContact()
    }

    var body: some View {
        Group {
            if let contact = contact {
                List {
                    // Batch 1：提醒中心——首页点进来、通知点进来，第一眼就是这里：
                    // 今年要发的卡（大图）+ 今年那行 + 发卡/打电话/发短信
                    Section {
                        if let hubCard = hubCard(for: contact) {
                            NavigationLink {
                                CardDetailView(cardID: hubCard.id)
                            } label: {
                                HStack(spacing: 12) {
                                    if let img = FileStorage.loadImage(fileName: hubCard.imageFile, subdir: "cards") {
                                        Image(uiImage: img)
                                            .resizable().scaledToFill()
                                            .frame(width: 72, height: 96)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(hubCard.name).font(.headline)
                                        Text(L("这张卡就是今年要发的"))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        } else {
                            Text(L("还没有给 TA 准备的卡片，去做一张吧。"))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        TextField(L("今年想送什么 / 想说什么"), text: thisYearNoteBinding(for: contact), axis: .vertical)
                            .lineLimit(2...4)
                        HStack(spacing: 20) {
                            if let hubCard = hubCard(for: contact) {
                                NavigationLink {
                                    CardDetailView(cardID: hubCard.id)
                                } label: {
                                    Label(L("发卡"), systemImage: "envelope")
                                }
                            } else {
                                Button {
                                    showingMaker = true
                                } label: {
                                    Label(L("去做一张卡"), systemImage: "paintbrush.pointed")
                                }
                            }
                            if let url = phoneURL(contact.phone, scheme: "tel") {
                                Link(destination: url) {
                                    Label(L("打电话"), systemImage: "phone")
                                }
                            }
                            if let url = smsURL(for: contact) {
                                Link(destination: url) {
                                    Label(L("发短信"), systemImage: "message")
                                }
                            }
                        }
                    } header: {
                        Text(L("提醒中心"))
                    } footer: {
                        Text(L("点「发卡」进卡片详情，用原来的方式分享或定时发送；「发短信」会把今年那行预填进短信内容。"))
                    }
                    .chunkyRow()

                    // Batch 1：本人的提醒设置——一屏看完，只改这个人
                    Section {
                        Picker(L("提前提醒"), selection: reminderAdvanceBinding(for: contact)) {
                            Text(L("跟随全局设置")).tag(Int?.none)
                            ForEach(ReminderSettings.advanceOptions, id: \.self) { d in
                                Text(d == 0 ? L("当天") : String(format: L("提前 %d 天"), d)).tag(Int?.some(d))
                            }
                        }
                        DatePicker(L("提醒时间"), selection: reminderTimeBinding(for: contact),
                                   displayedComponents: .hourAndMinute)
                        Picker(L("发送方式"), selection: reminderModeBinding(for: contact)) {
                            Text(L("跟随分组")).tag(SendMode?.none)
                            ForEach(SendMode.allCases) { mode in
                                Text(L(mode.rawValue)).tag(SendMode?.some(mode))
                            }
                        }
                        Picker(L("重复提醒间隔"), selection: reminderNagBinding(for: contact)) {
                            Text(L("跟随全局设置")).tag(Int?.none)
                            ForEach(ReminderSettings.nagIntervalOptions, id: \.self) { h in
                                Text(String(format: L("每 %d 小时"), h)).tag(Int?.some(h))
                            }
                        }
                        if hasReminderOverride(for: contact) {
                            Button {
                                clearReminderOverrides(for: contact)
                            } label: {
                                Label(L("恢复跟随全局设置"), systemImage: "arrow.uturn.backward")
                            }
                        }
                    } header: {
                        Text(L("提醒设置"))
                    } footer: {
                        VStack(alignment: .leading, spacing: 4) {
                            if settingsStore.settings.nagEnabled {
                                Text(String(format: L("现在生效：提前 %d 天，%02d:%02d，%@，每 %d 小时重复提醒"),
                                            settingsStore.settings.effectiveAdvance(for: contact),
                                            settingsStore.settings.effectiveHour(for: contact),
                                            settingsStore.settings.effectiveMinute(for: contact),
                                            L(settingsStore.settings.effectiveMode(for: contact).rawValue),
                                            settingsStore.settings.effectiveNagInterval(for: contact)))
                            } else {
                                Text(String(format: L("现在生效：提前 %d 天，%02d:%02d，%@"),
                                            settingsStore.settings.effectiveAdvance(for: contact),
                                            settingsStore.settings.effectiveHour(for: contact),
                                            settingsStore.settings.effectiveMinute(for: contact),
                                            L(settingsStore.settings.effectiveMode(for: contact).rawValue)))
                            }
                            Text(L("只改这个人，不改别人；选「跟随全局设置」就恢复成设置页里的全局值。改完会自动重新安排 TA 的生日提醒。"))
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .chunkyRow()

                    Section(L("基本信息")) {
                        LabeledContent(L("姓名"), value: contact.name)
                        LabeledContent(L("分组"), value: L(contact.group.rawValue))
                        LabeledContent(L("星标"), value: contact.isStarred ? L("是") : L("否"))
                        if let b = contact.birthday {
                            LabeledContent(L("生日"), value: b.displayText)
                            if let days = BirthdayCalc.daysUntil(b) {
                                LabeledContent(L("倒计时"), value: days == 0 ? L("就是今天！") : String(format: L("还有 %d 天"), days))
                            }
                            if let age = BirthdayCalc.turningAge(b) {
                                LabeledContent(L("将满"), value: String(format: L("%d 岁"), age))
                            }
                        } else {
                            LabeledContent(L("生日"), value: L("未填写"))
                        }
                        if !contact.email.isEmpty { LabeledContent(L("邮箱"), value: contact.email) }
                        if !contact.phone.isEmpty { LabeledContent(L("电话"), value: contact.phone) }
                        if !contact.note.isEmpty { LabeledContent(L("备注"), value: contact.note) }
                    }
                    .chunkyRow()

                    // 快捷联系：有电话才出打电话/发短信，有邮箱才出发邮件，点了跳系统电话/短信/邮件
                    if !contact.phone.isEmpty || !contact.email.isEmpty {
                        Section {
                            HStack(spacing: 20) {
                                if let url = phoneURL(contact.phone, scheme: "tel") {
                                    Link(destination: url) {
                                        Label(L("打电话"), systemImage: "phone")
                                    }
                                }
                                if let url = phoneURL(contact.phone, scheme: "sms") {
                                    Link(destination: url) {
                                        Label(L("发短信"), systemImage: "message")
                                    }
                                }
                                if !contact.email.isEmpty,
                                   let url = URL(string: "mailto:\(contact.email.trimmingCharacters(in: .whitespaces))") {
                                    Link(destination: url) {
                                        Label(L("发邮件"), systemImage: "envelope")
                                    }
                                }
                            }
                        }
                        .chunkyRow()
                    }

                    Section {
                        VoiceNoteSectionView(voiceNoteFile: voiceFileBinding(for: contact),
                                             noteText: noteTextBinding(for: contact))
                    } header: {
                        Text(L("关于 TA"))
                    } footer: {
                        Text(L("可选：录一段语音或写几句你对 TA 的想法——为什么 TA 重要、TA 喜欢什么。以后选卡、选礼物时能翻出来看。不填也可以。"))
                    }

                    Section {
                        Button {
                            CalendarManager.shared.addBirthdayEvent(for: contact) { msg in
                                calendarMessage = msg
                            }
                        } label: {
                            Label(L("加入系统日历"), systemImage: "calendar.badge.plus")
                        }
                        Button {
                            showingMaker = true
                        } label: {
                            Label(L("去做卡片"), systemImage: "paintbrush.pointed")
                        }
                        Button {
                            showingEdit = true
                        } label: {
                            Label(L("编辑联系人"), systemImage: "pencil")
                        }
                    }
                    .chunkyRow()

                    Section(L("TA 的卡片池")) {
                        let pool = cardStore.cards(for: contact.id)
                        if pool.isEmpty {
                            if let defaultCard = settingsStore.groupDefaultCard(for: contact.group, cardStore: cardStore),
                               contact.receivesGroupCard {
                                // 自己没备卡、所在分组设了默认卡、且本人在分组管理页被勾选接收：展示默认卡（不复制进个人卡池）
                                Text(String(format: L("分组默认卡 · %@"), L(contact.group.rawValue)))
                                    .font(.caption).foregroundStyle(.secondary)
                                NavigationLink {
                                    CardDetailView(cardID: defaultCard.id)
                                } label: {
                                    CardPoolRow(card: defaultCard)
                                }
                            } else {
                                Text(L("还没有给 TA 准备的卡片，去做一张吧。"))
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(pool) { card in
                                NavigationLink {
                                    CardDetailView(cardID: card.id)
                                } label: {
                                    CardPoolRow(card: card)
                                }
                            }
                        }
                    }
                    .chunkyRow()

                    Section {
                        Button(role: .destructive) {
                            // 先把 TA 名下的卡片改为未归属，避免留下悬空的 assignedContactID
                            for card in cardStore.cards(for: contact.id) {
                                var unassigned = card
                                unassigned.assignedContactID = nil
                                cardStore.update(unassigned)
                            }
                            // 录音文件连带删除，别在 voice/ 里留孤儿文件
                            if let vf = contact.voiceNoteFile {
                                FileStorage.deleteFile(fileName: vf, subdir: "voice")
                            }
                            contactStore.delete(contact)
                            NotificationManager.shared.reschedule(contacts: contactStore.contacts,
                                                                  settings: settingsStore.settings)
                            dismiss()
                        } label: {
                            Label(L("删除联系人"), systemImage: "trash")
                        }
                    }
                    .chunkyRow()
                }
                .sunnyScreen()
                .toolbarBackground(AppTheme.sunny, for: .navigationBar)
                .toolbarBackgroundVisibility(.visible, for: .navigationBar)
                .navigationTitle(contact.name)
                .sheet(isPresented: $showingEdit) {
                    ContactFormView(contact: contact)
                }
                .sheet(isPresented: $showingMaker) {
                    NavigationStack {
                        CardMakerView(preselectedContactID: contact.id)
                    }
                }
                .alert(L("日历"), isPresented: Binding(
                    get: { calendarMessage != nil },
                    set: { if !$0 { calendarMessage = nil } }
                )) {
                    Button(L("好")) { calendarMessage = nil }
                } message: {
                    Text(calendarMessage ?? "")
                }
            } else {
                ContentUnavailableView(L("联系人不存在"), systemImage: "person.slash")
            }
        }
    }
}

struct CardPoolRow: View {
    let card: CardDesign

    var body: some View {
        HStack(spacing: 10) {
            if let img = FileStorage.loadImage(fileName: card.imageFile, subdir: "cards") {
                Image(uiImage: img)
                    .resizable().scaledToFill()
                    .frame(width: 36, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 36, height: 48)
            }
            Text(card.name)
        }
    }
}

// MARK: - 联系人表单（添加/编辑）

struct ContactFormView: View {
    @EnvironmentObject var contactStore: ContactStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    let existing: BContact?

    @State private var name: String
    @State private var hasBirthday: Bool
    @State private var month: Int
    @State private var day: Int
    @State private var hasYear: Bool
    @State private var year: Int
    @State private var email: String
    @State private var phone: String
    @State private var isStarred: Bool
    @State private var group: ContactGroup
    @State private var note: String
    /// Batch 1：今年想送什么 / 想说什么
    @State private var thisYearNote: String
    @State private var voiceNoteFile: String?
    @State private var noteText: String
    /// 本次编辑里被替换/删除的旧录音文件名：保存时才真正删文件，
    /// 取消时不动它们，保证取消能恢复原状
    @State private var retiredVoiceFiles: [String] = []
    /// 本次编辑里新建的录音文件名：取消时删掉，不留孤儿文件
    @State private var sessionVoiceFiles: [String] = []

    init(contact: BContact?) {
        self.existing = contact
        _name = State(initialValue: contact?.name ?? "")
        _hasBirthday = State(initialValue: contact?.birthday != nil)
        _month = State(initialValue: contact?.birthday?.month ?? 1)
        _day = State(initialValue: contact?.birthday?.day ?? 1)
        _hasYear = State(initialValue: contact?.birthday?.year != nil)
        _year = State(initialValue: contact?.birthday?.year ?? 1990)
        _email = State(initialValue: contact?.email ?? "")
        _phone = State(initialValue: contact?.phone ?? "")
        _isStarred = State(initialValue: contact?.isStarred ?? false)
        _group = State(initialValue: contact?.group ?? .friend)
        _note = State(initialValue: contact?.note ?? "")
        _thisYearNote = State(initialValue: contact?.thisYearNote ?? "")
        _voiceNoteFile = State(initialValue: contact?.voiceNoteFile)
        _noteText = State(initialValue: contact?.noteText ?? "")
    }

    private var daysInMonth: Int {
        switch month {
        case 2: return 29
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("姓名")) {
                    TextField(L("姓名"), text: $name)
                }
                .chunkyRow()
                Section(L("生日")) {
                    Toggle(L("有生日"), isOn: $hasBirthday)
                    if hasBirthday {
                        Picker(L("月"), selection: $month) {
                            ForEach(1...12, id: \.self) { Text(monthDisplayName($0)).tag($0) }
                        }
                        Picker(L("日"), selection: $day) {
                            ForEach(1...daysInMonth, id: \.self) { Text(String(format: L("%d日"), $0)).tag($0) }
                        }
                        Toggle(L("填写年份"), isOn: $hasYear)
                        if hasYear {
                            Picker(L("年份"), selection: $year) {
                                ForEach(Array((1920...2026).reversed()), id: \.self) { y in
                                    Text(String(y)).tag(y)
                                }
                            }
                        } else {
                            Text(L("不填年份也可以，只记月和日。"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .chunkyRow()
                Section(L("分组与星标")) {
                    Picker(L("分组"), selection: $group) {
                        ForEach(ContactGroup.allCases) { g in
                            Text(L(g.rawValue)).tag(g)
                        }
                    }
                    Toggle(L("星标（重要联系人）"), isOn: $isStarred)
                }
                .chunkyRow()
                Section(L("联系方式")) {
                    TextField(L("邮箱"), text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField(L("电话"), text: $phone)
                        .keyboardType(.phonePad)
                }
                .chunkyRow()
                Section(L("备注")) {
                    TextField(L("备注（喜好、忌口等）"), text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
                .chunkyRow()
                Section(L("今年想送什么 / 想说什么")) {
                    TextField(L("今年想送什么 / 想说什么"), text: $thisYearNote, axis: .vertical)
                        .lineLimit(2...4)
                }
                .chunkyRow()
                Section {
                    VoiceNoteSectionView(
                        voiceNoteFile: $voiceNoteFile,
                        noteText: $noteText,
                        onRetireFile: { name in
                            if !retiredVoiceFiles.contains(name) {
                                retiredVoiceFiles.append(name)
                            }
                        },
                        onNewRecording: { name in
                            if !sessionVoiceFiles.contains(name) {
                                sessionVoiceFiles.append(name)
                            }
                        }
                    )
                } header: {
                    Text(L("关于 TA（可选）"))
                } footer: {
                    Text(L("想说说你对 TA 的想法吗？为什么 TA 重要、TA 喜欢什么——录一段语音或写下来，以后选卡、选礼物时能翻出来看。不填也可以。"))
                }
            }
            .sunnyScreen()
            .navigationTitle(existing == nil ? L("添加联系人") : L("编辑联系人"))
            .onChange(of: month) { _, _ in
                // 切到小月时把日钳到该月最大天数，避免界面选 31 日、存进去却是别的值
                day = min(day, daysInMonth)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("取消")) { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("保存")) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func cancel() {
        // 取消：删掉本次新建的录音文件，原有录音与已存笔记保持不变
        for name in sessionVoiceFiles {
            FileStorage.deleteFile(fileName: name, subdir: "voice")
        }
        dismiss()
    }

    private func save() {
        let safeDay = min(day, daysInMonth)
        let bday: BirthdayDate? = hasBirthday
            ? BirthdayDate(year: hasYear ? year : nil, month: month, day: safeDay)
            : nil
        let finalNoteText: String? = noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : noteText
        let finalThisYearNote: String? = thisYearNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : thisYearNote
        if var contact = existing {
            contact.name = name
            contact.birthday = bday
            contact.email = email
            contact.phone = phone
            contact.isStarred = isStarred
            contact.group = group
            contact.note = note
            contact.voiceNoteFile = voiceNoteFile
            contact.noteText = finalNoteText
            contact.thisYearNote = finalThisYearNote
            contactStore.update(contact)
        } else {
            contactStore.add(BContact(name: name, birthday: bday, email: email,
                                      phone: phone, isStarred: isStarred,
                                      group: group, note: note,
                                      voiceNoteFile: voiceNoteFile,
                                      noteText: finalNoteText,
                                      thisYearNote: finalThisYearNote))
        }
        // 保存落盘后，删掉本次被替换/删除的旧录音文件（最终在用的那个不删）
        for name in retiredVoiceFiles where name != voiceNoteFile {
            FileStorage.deleteFile(fileName: name, subdir: "voice")
        }
        NotificationManager.shared.reschedule(contacts: contactStore.contacts,
                                              settings: settingsStore.settings)
        dismiss()
    }
}

// MARK: - 做卡片：基础类型

struct RGBAColor: Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double = 1.0
    var color: Color { Color(red: r, green: g, blue: b, opacity: a) }
    var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: a) }

    static let palette: [RGBAColor] = [
        RGBAColor(r: 0.10, g: 0.10, b: 0.10),  // 黑
        RGBAColor(r: 0.85, g: 0.20, b: 0.25),  // 红
        RGBAColor(r: 0.95, g: 0.55, b: 0.15),  // 橙
        RGBAColor(r: 0.95, g: 0.80, b: 0.20),  // 黄
        RGBAColor(r: 0.25, g: 0.65, b: 0.30),  // 绿
        RGBAColor(r: 0.15, g: 0.55, b: 0.75),  // 蓝
        RGBAColor(r: 0.45, g: 0.30, b: 0.75),  // 紫
        RGBAColor(r: 0.95, g: 0.45, b: 0.65),  // 粉
        RGBAColor(r: 0.55, g: 0.35, b: 0.20),  // 棕
        RGBAColor(r: 0.60, g: 0.60, b: 0.62),  // 灰
        RGBAColor(r: 1.00, g: 1.00, b: 1.00),  // 白
        RGBAColor(r: 0.85, g: 0.65, b: 0.10)   // 金
    ]
}

enum PaperKind: String, CaseIterable, Identifiable {
    case white = "白卡纸"
    case kraft = "牛皮纸"
    case pink = "粉纸"
    case blue = "蓝纸"
    case cream = "奶油纸"
    case glitter = "亮粉纸"
    case watercolor = "水彩纸"
    case stripes = "底纹纸"
    var id: String { rawValue }
}

struct PaperView: View {
    let kind: PaperKind

    var body: some View {
        ZStack {
            base
            if kind == .glitter {
                SparkleOverlay()
            }
            if kind == .stripes {
                StripeOverlay()
            }
        }
    }

    @ViewBuilder
    private var base: some View {
        switch kind {
        case .white:
            Color.white
        case .kraft:
            Color(red: 0.76, green: 0.60, blue: 0.42)
        case .pink:
            Color(red: 0.98, green: 0.85, blue: 0.88)
        case .blue:
            Color(red: 0.82, green: 0.90, blue: 0.98)
        case .cream:
            Color(red: 0.99, green: 0.96, blue: 0.87)
        case .glitter:
            LinearGradient(colors: [Color(red: 0.98, green: 0.75, blue: 0.85),
                                    Color(red: 0.90, green: 0.60, blue: 0.80)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .watercolor:
            LinearGradient(colors: [Color(red: 0.90, green: 0.95, blue: 0.92),
                                    Color(red: 0.85, green: 0.90, blue: 0.98),
                                    Color(red: 0.96, green: 0.90, blue: 0.94)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .stripes:
            Color(red: 0.97, green: 0.97, blue: 0.95)
        }
    }
}

struct SparkleOverlay: View {
    var body: some View {
        Canvas { context, size in
            // 固定伪随机亮点（用确定性序列，保证渲染一致）
            var seed: UInt64 = 42
            func nextRand() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double((seed >> 33) % 1000) / 1000.0
            }
            for _ in 0..<70 {
                let x = nextRand() * size.width
                let y = nextRand() * size.height
                let r = 1.0 + nextRand() * 1.8
                let rect = CGRect(x: x, y: y, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect),
                             with: .color(.white.opacity(0.55 + nextRand() * 0.4)))
            }
        }
        .allowsHitTesting(false)
    }
}

struct StripeOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let step: CGFloat = 18
                var x: CGFloat = -geo.size.height
                while x < geo.size.width + geo.size.height {
                    path.move(to: CGPoint(x: x, y: geo.size.height))
                    path.addLine(to: CGPoint(x: x + geo.size.height, y: 0))
                    x += step
                }
            }
            .stroke(Color(red: 0.85, green: 0.80, blue: 0.70).opacity(0.5), lineWidth: 5)
        }
        .allowsHitTesting(false)
    }
}

enum BrushKind: String, CaseIterable, Identifiable {
    case crayon = "蜡笔"
    case marker = "记号笔"
    case glitter = "亮粉笔"
    case fine = "细线笔"
    case watercolor = "水彩笔"
    var id: String { rawValue }

    var lineWidth: CGFloat {
        switch self {
        case .crayon: return 10
        case .marker: return 6
        case .glitter: return 5
        case .fine: return 2
        case .watercolor: return 16
        }
    }
    var opacity: Double {
        switch self {
        case .crayon: return 0.55
        case .marker: return 0.85
        case .glitter: return 0.9
        case .fine: return 0.95
        case .watercolor: return 0.16
        }
    }
}

struct Stroke: Identifiable {
    var id = UUID()
    var points: [CGPoint]
    var brush: BrushKind
    var color: RGBAColor
}

struct StrokeRenderView: View {
    let strokes: [Stroke]

    var body: some View {
        Canvas { context, _ in
            for stroke in strokes {
                drawStroke(stroke, in: &context)
            }
        }
        .allowsHitTesting(false)
    }

    private func pathFrom(_ points: [CGPoint], offset: CGSize = .zero) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.x + offset.width, y: first.y + offset.height))
        if points.count == 1 {
            path.addLine(to: CGPoint(x: first.x + offset.width + 0.1, y: first.y + offset.height))
        } else {
            for p in points.dropFirst() {
                path.addLine(to: CGPoint(x: p.x + offset.width, y: p.y + offset.height))
            }
        }
        return path
    }

    private func drawStroke(_ stroke: Stroke, in context: inout GraphicsContext) {
        guard !stroke.points.isEmpty else { return }
        let baseColor = stroke.color.color.opacity(stroke.brush.opacity)
        let style = StrokeStyle(lineWidth: stroke.brush.lineWidth, lineCap: .round, lineJoin: .round)
        switch stroke.brush {
        case .crayon:
            // 粗糙感：同一路径以微小偏移叠画三次
            for off in [CGSize(width: -1.2, height: 0.5), CGSize(width: 1.0, height: -0.8), CGSize(width: 0.3, height: 1.1)] {
                context.stroke(pathFrom(stroke.points, offset: off),
                               with: .color(baseColor.opacity(0.35)), style: style)
            }
        case .glitter:
            context.stroke(pathFrom(stroke.points), with: .color(baseColor), style: style)
            // 沿路径撒亮粉点
            for (i, p) in stroke.points.enumerated() where i % 3 == 0 {
                let rect = CGRect(x: p.x - 1.6, y: p.y - 1.6, width: 3.2, height: 3.2)
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.9)))
            }
        case .watercolor:
            context.stroke(pathFrom(stroke.points), with: .color(baseColor), style: style)
            context.stroke(pathFrom(stroke.points, offset: CGSize(width: 1.5, height: 1.0)),
                           with: .color(baseColor.opacity(0.10)), style: style)
        case .marker, .fine:
            context.stroke(pathFrom(stroke.points), with: .color(baseColor), style: style)
        }
    }
}

// MARK: - 画布元素（贴纸/文字）

enum ElementKind {
    case emoji(String)
    case photo(String)              // stickers 子目录下的文件名
    case drawing(String)            // drawings 子目录下的文件名（画笔笔迹转成的透明底图层）
    case text(String, Double, RGBAColor)  // 内容、字号、颜色
    case bubble(String)             // 对话气泡：话直接写在气泡里、看得见（成品是静态图，必须可见）
}

/// 对话气泡的样子：白色圆角气泡 + 左下小尾巴，话写在气泡里面。
/// 编辑器（ElementVisualView）与成品渲染（CardContentView 走同一个 ElementVisualView）共用，所见即所存。
struct SpeechBubbleView: View {
    let message: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // 小尾巴：一块白色小方块转 45°，从气泡左下探出（offset 只改渲染位置、不占布局）
            Rectangle()
                .fill(Color.white)
                .frame(width: 16, height: 16)
                .rotationEffect(.degrees(45))
                .offset(x: 20, y: 6)
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .padding(10)
                .frame(width: 150)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
                )
        }
    }
}

/// 贴纸动态（她 2026-11-03 定）：悬浮 = 像小幽灵那样低频率、左右小幅晃动；不动 = 完全静止。
/// 只对主体贴纸（照片/emoji）有意义；文字与画笔图层是印在纸上的，恒为静止。
/// CardElement 只是编辑会话内的临时状态、不落盘（存盘的只有渲染好的成品 PNG），故加字段无存档兼容问题。
enum StickerMotion {
    case floating
    case still
}

/// 悬浮的晃法（给定组合，她 2026-11-03 定：由 user 从给定组合里选，不做自由拼配）
enum FloatPattern: String, CaseIterable {
    case side = "左右"          // 只左右晃——她原话的小幽灵默认款
    case upDown = "上下"        // 只上下浮
    case drift = "左右+上下"    // 两轴相位错开，绕着小圈漂
    case rocking = "摇摆"       // 以轻微旋转为主的摇摆，带一点左右
}

struct CardElement: Identifiable {
    var id = UUID()
    var kind: ElementKind
    var x: CGFloat
    var y: CGFloat
    var scale: CGFloat = 1.0
    var rotation: Double = 0
    /// 新贴纸默认悬浮，让她一贴上就能看到效果；不想要的那只单独改成不动
    var motion: StickerMotion = .floating
    /// 悬浮晃法，默认「左右」（她的小幽灵口径）
    var floatPattern: FloatPattern = .side
    /// 悬浮幅度（最大偏移，单位 pt）：user 自己拖滑杆调大调小，范围 2–12，默认 4（小幅）
    var floatAmplitude: CGFloat = 4
    /// 水平镜像（主体贴纸用）：true 时左右翻面
    var flipX: Bool = false
    /// 不透明度（主体贴纸用）：1 = 完全不透明，滑杆下限 0.3
    var opacity: Double = 1.0
}

struct ElementVisualView: View {
    let kind: ElementKind

    var body: some View {
        switch kind {
        case .emoji(let symbol):
            Text(symbol).font(.system(size: 46))
        case .photo(let fileName):
            if let img = FileStorage.loadImage(fileName: fileName, subdir: "stickers") {
                Image(uiImage: img)
                    .resizable().scaledToFit()
                    .frame(width: 130, height: 130)
            } else {
                Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
            }
        case .drawing(let fileName):
            // 画笔图层是整卡尺寸的透明底 PNG，按原位置原大小铺回画布，所见即所画
            if let img = FileStorage.loadImage(fileName: fileName, subdir: "drawings") {
                Image(uiImage: img)
                    .resizable().scaledToFit()
                    .frame(width: CardMakerView.cardSize.width, height: CardMakerView.cardSize.height)
            } else {
                Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
            }
        case .text(let content, let fontSize, let color):
            Text(content)
                .font(.system(size: fontSize, weight: .medium, design: .rounded))
                .foregroundStyle(color.color)
                .multilineTextAlignment(.center)
                // 与编辑器命中框同尺寸，保证编辑所见与成品渲染排版一致
                .frame(width: 240, height: 80)
        case .bubble(let message):
            SpeechBubbleView(message: message)
        }
    }
}

struct EditorElementView: View {
    @Binding var element: CardElement
    let isSelected: Bool
    let onSelect: () -> Void
    /// 删除本元素（父视图按 id 删并清选中，与已选面板的删除按钮共用一条路径）；
    /// 选中时右上角的 ❌ 点它即删，不必再去面板里找删除按钮
    let onDelete: () -> Void
    /// 是否处于站起来预览：预览中本元素的位置/大小/角度与编辑时完全一致，
    /// 只是手势锁定；躺下的是纸，不是元素（见 CardMakerView 的纸组变换）。
    /// 设成「悬浮」的贴纸在预览中照样悬浮（那正是要预览的效果），设成「不动」的完全静止。
    let standPreview: Bool
    @State private var dragStart: CGPoint? = nil
    @State private var scaleStart: CGFloat? = nil
    @State private var rotationStart: Double? = nil
    /// 点按蹦跳的瞬时缩放倍数：主体贴纸被点中时跳到 1.18 再弹簧落回 1；
    /// 文字/画笔图层不跳，恒为 1（见 onTapGesture）
    @State private var bounce: CGFloat = 1

    /// 双指放大元素的缩放上下限：上限 8 倍（她 2026-11-03 反馈原来的 4 倍不够大），下限沿用 0.2；
    /// 全文件只有双指手势这一处钳制元素缩放，成品渲染（CardContentView）不钳、按存下的值原样画
    static let maxElementScale: CGFloat = 8.0
    static let minElementScale: CGFloat = 0.2

    /// 每种元素的大致命中尺寸（让每个元素只占自己的地盘，不挡住画布和其他元素）
    private var hitSize: CGSize {
        switch element.kind {
        case .emoji: return CGSize(width: 64, height: 64)
        case .photo: return CGSize(width: 130, height: 130)
        case .drawing: return CardMakerView.cardSize
        case .text: return CGSize(width: 240, height: 80)
        case .bubble: return CGSize(width: 150, height: 90)
        }
    }

    /// 贴纸类元素（照片/emoji/画笔图层）：历史上参与过待机动画，现悬浮只给主体贴纸（见 isSubject）；
    /// 文字与画笔图层是"印"在纸上的，不悬浮
    private var isStickerLike: Bool {
        switch element.kind {
        case .photo, .emoji, .drawing, .bubble: return true
        case .text: return false
        }
    }

    /// 主体贴纸（照片/emoji/气泡）：预览里不随纸躺下、保持原样，脚下带一团接触影；
    /// 文字与画笔图层是印在纸上的内容，随纸组一起躺下（分层在 CardMakerView 里做）。
    /// 气泡装的是"人说的话"，跟说话的人（贴纸）站在一起，所以也算主体。
    private var isSubject: Bool {
        switch element.kind {
        case .photo, .emoji, .bubble: return true
        case .drawing, .text: return false
        }
    }

    // MARK: 悬浮（她 2026-11-03 定版，取代旧的呼吸待机动画）
    // 每只主体贴纸可选「悬浮 / 不动」：
    // - 悬浮：像小幽灵那样低频率晃动——周期 3.8–4.6 秒（比旧呼吸慢得多），
    //   晃法从给定组合里选（左右 / 上下 / 左右+上下 / 摇摆），幅度由 user 拖滑杆调（2–12 pt，默认 4）。
    // - 不动：完全静止，连 TimelineView 都不挂。
    // 悬浮在编辑态和站起来预览中都生效；被手势拖动/缩放/旋转的那一刻暂停，松手恢复。
    // 保存的成品 PNG 走 CardContentView（无此动画），永远是静止图，悬浮只活在 App 内的活画面里。

    /// 每只贴纸自己的相位（由元素 id 的字节稳定推导，重启 App 也一致），彼此不同步
    private var floatPhase: Double {
        let u = element.id.uuid
        let seed = Int(u.0) &+ Int(u.1) &* 7 &+ Int(u.2) &* 13 &+ Int(u.3) &* 29 &+ Int(u.4) &* 43
        return Double(seed % 628) / 100.0
    }

    /// 低频率：每只贴纸自己的周期 3.8–4.6 秒（小幽灵的速度），同样由 id 稳定推导
    private var floatPeriod: Double {
        3.8 + Double(Int(element.id.uuid.5) % 80) / 100.0
    }

    private var floatActive: Bool {
        isSubject && element.motion == .floating
            && dragStart == nil && scaleStart == nil && rotationStart == nil
    }

    /// 按晃法组合算这一刻的偏移与旋转：幅度 A = user 调的 floatAmplitude（pt）
    private func floatOffset(at date: Date) -> CGSize {
        guard floatActive else { return .zero }
        let a = Double(element.floatAmplitude)
        let w = date.timeIntervalSinceReferenceDate * 2 * Double.pi / floatPeriod + floatPhase
        switch element.floatPattern {
        case .side:
            return CGSize(width: a * sin(w), height: 0)
        case .upDown:
            return CGSize(width: 0, height: a * 0.8 * sin(w))
        case .drift:
            // 两轴同频、相位错开 1.3，轨迹是一个小椭圆，像漂着的小幽灵
            return CGSize(width: a * sin(w), height: a * 0.55 * sin(w + 1.3))
        case .rocking:
            return CGSize(width: a * 0.4 * sin(w), height: 0)
        }
    }

    private func floatRotation(at date: Date) -> Double {
        guard floatActive, element.floatPattern == .rocking else { return 0 }
        let w = date.timeIntervalSinceReferenceDate * 2 * Double.pi / floatPeriod + floatPhase
        // 幅度每 1 pt 折合约 0.35°：默认 4 pt ≈ ±1.4°，调满 12 pt ≈ ±4.2°
        return Double(element.floatAmplitude) * 0.35 * sin(w)
    }

    /// 贴纸本体：设成悬浮的主体贴纸走 TimelineView 逐帧算偏移，其余一律静态渲染；
    /// 本元素自身永远不做 3D 变换——站起来预览里躺下的是纸，贴纸只做平面内的悬浮偏移
    @ViewBuilder
    private var stickerVisual: some View {
        if isSubject && element.motion == .floating {
            TimelineView(.animation) { context in
                ElementVisualView(kind: element.kind)
                    .scaleEffect(x: element.flipX ? -1 : 1, y: 1)
                    .opacity(element.opacity)
                    .rotationEffect(.degrees(floatRotation(at: context.date)))
                    .offset(floatOffset(at: context.date))
                    .frame(width: hitSize.width, height: hitSize.height)
            }
        } else {
            ElementVisualView(kind: element.kind)
                .scaleEffect(x: element.flipX ? -1 : 1, y: 1)
                .opacity(element.opacity)
                .frame(width: hitSize.width, height: hitSize.height)
        }
    }

    var body: some View {
        ZStack {
            // 预览中主体贴纸脚下的接触影：屏幕空间里一团不旋转的软影，
            // 让原样不动的贴纸看起来"落"在躺下的纸上方；编辑时不显示
            if isSubject && standPreview {
                Ellipse()
                    .fill(Color.black.opacity(0.25))
                    .frame(width: hitSize.width * 0.92, height: 12)
                    .blur(radius: 5)
                    .offset(y: hitSize.height / 2 - 4)
            }
            stickerVisual
        }
            .frame(width: hitSize.width, height: hitSize.height)
            .overlay {
                if isSelected && !standPreview {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor, lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
            }
            // bounce 是点按蹦跳的瞬时倍数，与 element.scale 相乘；绕中心缩放，
            // 下面的 offset 只减未缩放的半宽/半高，布局位置不受 bounce 影响
            .scaleEffect(element.scale * bounce)
            .rotationEffect(.degrees(element.rotation))
            // 中心对齐到 (x, y)：缩放是绕中心的视觉变换，不改变布局中心，
            // 偏移只减未缩放的半宽/半高，否则缩放后编辑位置会与成品渲染位置错位
            .offset(x: element.x - hitSize.width / 2,
                    y: element.y - hitSize.height / 2)
            .onTapGesture {
                // 预览只是看效果，不选不改；编辑时点选本元素
                if !standPreview {
                    onSelect()
                    // 点按蹦跳：只有主体贴纸跳——先无动画顶到 1.18，再用弹簧落回 1
                    if isSubject {
                        bounce = 1.18
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.45)) {
                            bounce = 1
                        }
                    }
                }
            }
            .gesture(
                DragGesture(coordinateSpace: .named("cardCanvas"))
                    .onChanged { value in
                        guard !standPreview else { return }   // 预览中不许拖动，位置只由编辑决定
                        if dragStart == nil { dragStart = CGPoint(x: element.x, y: element.y) }
                        let rawX = (dragStart?.x ?? element.x) + value.translation.width
                        let rawY = (dragStart?.y ?? element.y) + value.translation.height
                        // 中心钳制在画布内，元素拖不出去、不会丢
                        element.x = min(max(rawX, 0), CardMakerView.cardSize.width)
                        element.y = min(max(rawY, 0), CardMakerView.cardSize.height)
                        onSelect()
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        guard !standPreview else { return }
                        if scaleStart == nil { scaleStart = element.scale }
                        element.scale = min(Self.maxElementScale,
                                            max(Self.minElementScale, (scaleStart ?? 1.0) * value.magnification))
                    }
                    .onEnded { _ in scaleStart = nil }
            )
            .simultaneousGesture(
                RotationGesture()
                    .onChanged { value in
                        guard !standPreview else { return }
                        if rotationStart == nil { rotationStart = element.rotation }
                        element.rotation = (rotationStart ?? 0) + value.degrees
                    }
                    .onEnded { _ in rotationStart = nil }
            )
            // 删除 ❌：只在选中且非预览时出现，挂在最外层——不在 scaleEffect/rotationEffect 里，
            // 大小恒定好点；位置对齐命中框右上角再向外挪一点。它在手势修饰符之外，
            // 点它不会触发本元素的点选/拖动（按钮自己吃掉这次点按）。
            .overlay(alignment: .topTrailing) {
                if isSelected && !standPreview {
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, .red)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 8, y: -8)
                }
            }
    }
}

/// 卡片成品视图（编辑保存时用 ImageRenderer 渲染的就是它）
struct CardContentView: View {
    let paper: PaperKind
    var customPaperFile: String? = nil
    let strokes: [Stroke]
    let elements: [CardElement]
    let size: CGSize

    var body: some View {
        ZStack {
            PaperBackgroundView(paper: paper, customFile: customPaperFile)
            StrokeRenderView(strokes: strokes)
            ForEach(elements) { element in
                ElementVisualView(kind: element.kind)
                    .scaleEffect(x: element.scale * (element.flipX ? -1 : 1), y: element.scale)
                    .opacity(element.opacity)
                    .rotationEffect(.degrees(element.rotation))
                    .position(x: element.x, y: element.y)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

/// 整张打开的卡（多面拼版）：把每一面（各 330×440）按卡片形式拼成一张完整的纸。
/// 一张纸不走这里（saveCard 仍走单面 CardContentView 原路）；对折 = 横排 2 面（660×440）；
/// 四折 = 2×2（660×880），上排 [封面，内页左]、下排 [内页右，背面]。
struct CardSheetView: View {
    let panels: [CardPanelState]
    let format: CardFormat

    private func panelView(_ idx: Int) -> CardContentView {
        // 面数不足时兜底空白面，绝不越界崩溃
        let p = panels.indices.contains(idx) ? panels[idx] : CardPanelState()
        return CardContentView(paper: p.paper, customPaperFile: p.customPaperFile,
                               strokes: p.strokes, elements: p.elements,
                               size: CardMakerView.cardSize)
    }

    var body: some View {
        switch format {
        case .flat:
            panelView(0)   // 兜底：正常保存路径不会以 flat 走到这里
        case .bifold:
            HStack(spacing: 0) {
                panelView(0)
                panelView(1)
            }
        case .quarter:
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    panelView(0)
                    panelView(1)
                }
                HStack(spacing: 0) {
                    panelView(2)
                    panelView(3)
                }
            }
        }
    }
}

// MARK: - 照片抠图（Vision 前景分割 + 白边贴纸）

enum CutoutHelper {
    /// UIImage.Orientation → CGImagePropertyOrientation（两者 rawValue 不通用，逐个映射）
    private nonisolated static func cgOrientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    /// 把照片数据做成带白边的贴纸 PNG，存到 Documents/stickers/，返回文件名；失败返回 nil
    /// 白边做法（按定版规格）：不整体放大剪影（那会跟随抠图锯齿、粗细不均），
    /// 而是把 alpha 先轻微模糊平滑台阶，再按固定半径做形态学膨胀，
    /// 得到一圈粗细恒定、边缘平滑的白色轮廓，视觉上接近一条完整的线。
    nonisolated static func makeStickerPNG(from data: Data) -> String? {
        guard let source = UIImage(data: data), let cg = source.cgImage else { return nil }
        do {
            let request = VNGenerateForegroundInstanceMaskRequest()
            // 带上 EXIF 方向，否则普通相机照片的贴纸会侧倒
            let handler = VNImageRequestHandler(cgImage: cg,
                                                orientation: cgOrientation(source.imageOrientation),
                                                options: [:])
            try handler.perform([request])
            guard let observation = request.results?.first else { return nil }
            let maskedBuffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: false)
            let maskedCI0 = CIImage(cvPixelBuffer: maskedBuffer)
            let context = CIContext()
            guard let masked = context.createCGImage(maskedCI0, from: maskedCI0.extent) else { return nil }

            let maskedCI = CIImage(cgImage: masked)
            let extent = maskedCI.extent

            // 第 0 步·主体预扩张：Vision 分割常把发梢、发丝这类边缘像素削掉一圈（严重时像把头削没）。
            //    先把主体按短边 0.7%（钳 4–14 px）形态学外扩一次，再把原主体盖回去合成 subjectCI：
            //    扩出的那一圈带着边缘颜色的半透明像素，被削掉的轮廓就这样找回来。
            //    后面的白边从 subjectCI 往外做，白边规格本身（模糊 2.0 + 半径 2% 钳 10–40）一字不动。
            let preRadius = min(14, max(4, min(extent.width, extent.height) * 0.007))
            var subjectCI = maskedCI
            if let preDilate = CIFilter(name: "CIMorphologyMaximum") {
                preDilate.setValue(maskedCI, forKey: kCIInputImageKey)
                preDilate.setValue(preRadius, forKey: kCIInputRadiusKey)
                if let grown = preDilate.outputImage?.cropped(to: extent),
                   let over = CIFilter(name: "CISourceOverCompositing") {
                    over.setValue(maskedCI, forKey: kCIInputImageKey)
                    over.setValue(grown, forKey: kCIInputBackgroundImageKey)
                    if let composed = over.outputImage {
                        subjectCI = composed.cropped(to: extent)
                    }
                }
            }

            // 白边粗细：按短边的 2% 取，钳在 10–40 像素之间——全图恒定一圈
            let borderRadius = min(40, max(10, min(extent.width, extent.height) * 0.02))

            // 1) 轻微模糊：把抠图边缘的像素台阶抹平
            var borderMask = subjectCI
            if let blur = CIFilter(name: "CIGaussianBlur") {
                blur.setValue(subjectCI, forKey: kCIInputImageKey)
                blur.setValue(2.0, forKey: kCIInputRadiusKey)
                if let out = blur.outputImage {
                    borderMask = out.cropped(to: extent)
                }
            }
            // 2) 固定半径膨胀：轮廓均匀外扩一圈
            if let dilate = CIFilter(name: "CIMorphologyMaximum") {
                dilate.setValue(borderMask, forKey: kCIInputImageKey)
                dilate.setValue(borderRadius, forKey: kCIInputRadiusKey)
                if let out = dilate.outputImage {
                    borderMask = out.cropped(to: extent)
                }
            }

            // 白色剪影：以膨胀后的 alpha 为遮罩的纯白图
            let white = CIImage(color: CIColor.white).cropped(to: extent)
            let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent)
            guard let blend = CIFilter(name: "CIBlendWithAlphaMask") else { return nil }
            blend.setValue(white, forKey: kCIInputImageKey)
            blend.setValue(clear, forKey: kCIInputBackgroundImageKey)
            blend.setValue(borderMask, forKey: kCIInputMaskImageKey)
            guard let outImage = blend.outputImage,
                  let whiteCG = context.createCGImage(outImage, from: extent) else { return nil }

            // 画上去的主体用预扩张后的 subjectCI（渲染尺寸与原 masked 图同 extent，不变），
            // 找回的边缘像素才真的出现在贴纸上、压在白边剪影之上
            guard let subjectCG = context.createCGImage(subjectCI, from: extent) else { return nil }
            let maskedImage = UIImage(cgImage: subjectCG)
            let whiteImage = UIImage(cgImage: whiteCG)
            let pad = borderRadius + 12
            let canvasSize = CGSize(width: CGFloat(masked.width) + pad * 2,
                                    height: CGFloat(masked.height) + pad * 2)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
            let sticker = renderer.image { _ in
                // 剪影与主体同尺寸同原点叠放：膨胀出的那一圈就是白边
                let rect = CGRect(x: pad, y: pad,
                                  width: maskedImage.size.width,
                                  height: maskedImage.size.height)
                whiteImage.draw(in: rect)
                maskedImage.draw(in: rect)
            }
            guard let png = sticker.pngData() else { return nil }
            let fileName = "sticker-\(UUID().uuidString).png"
            let url = FileStorage.url(for: fileName, subdir: "stickers")
            try png.write(to: url)
            return fileName
        } catch {
            return nil
        }
    }

    /// 不抠图、直接用原图做贴纸（抠图把主体削残时的兜底）：重绘一次把 EXIF 方向摆正、
    /// 长边压到 1200，按与抠图贴纸相同的文件名规则存进 Documents/stickers/，返回文件名；失败返回 nil。
    /// 必须是 PNG：贴纸库列表（stickerFileNames）只认 .png，这样原图贴纸也会进「我的贴纸」。
    /// 代价：贴纸是完整的长方形照片，没有抠图的轮廓和白边。
    nonisolated static func makeOriginalPNG(from data: Data) -> String? {
        guard let source = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 1200
        let size = source.size   // UIImage.size 是方向校正后的尺寸；draw 时按 imageOrientation 摆正像素
        let longest = max(size.width, size.height)
        var target = size
        if longest > maxSide {
            let ratio = maxSide / longest
            target = CGSize(width: size.width * ratio, height: size.height * ratio)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let normalized = renderer.image { _ in
            source.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let png = normalized.pngData() else { return nil }
        let fileName = "sticker-\(UUID().uuidString).png"
        do {
            try png.write(to: FileStorage.url(for: fileName, subdir: "stickers"))
            return fileName
        } catch {
            return nil
        }
    }
}

/// 自定义纸张：把用户拍/选的照片存成纸面图（长边压到 1200 再存 JPEG，文件别太大），返回文件名
enum PaperImageHelper {
    static func saveAsPaper(_ image: UIImage) -> String? {
        let maxSide: CGFloat = 1200
        let size = image.size
        let longest = max(size.width, size.height)
        var target = size
        if longest > maxSide {
            let ratio = maxSide / longest
            target = CGSize(width: size.width * ratio, height: size.height * ratio)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let data = scaled.jpegData(compressionQuality: 0.85) else { return nil }
        let fileName = "paper-\(UUID().uuidString).jpg"
        do {
            try data.write(to: FileStorage.url(for: fileName, subdir: "papers"))
            return fileName
        } catch {
            return nil
        }
    }
}

/// 卡片纸面：选了自定义纸图就铺满那张照片，否则用预设纸
struct PaperBackgroundView: View {
    let paper: PaperKind
    let customFile: String?

    var body: some View {
        if let file = customFile,
           let img = FileStorage.loadImage(fileName: file, subdir: "papers") {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
        } else {
            PaperView(kind: paper)
        }
    }
}

/// 系统相机拍照（做贴纸用）：拍完把原图交回调用方走抠图流程
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - 做卡片主界面

/// 卡片形式（她 2026-11-03 定）：一张纸 / 对折打开（折一次，2 面）/ 四折打开（折两次，折起是整纸 1/4，4 面）。
/// 形式只活在编辑会话里，不落盘——存进卡片库的永远是整张打开渲染成的一张 PNG（见 saveCard）。
enum CardFormat: String, CaseIterable {
    case flat = "一张纸"
    case bifold = "对折打开"
    case quarter = "四折打开"

    /// 各面的名字（中文原文即 L() 的键，显示时走 L(name)）；一张纸没有分面概念，返回空
    var panelNames: [String] {
        switch self {
        case .flat: return []
        case .bifold: return ["封面", "内页"]
        case .quarter: return ["封面", "内页左", "内页右", "背面"]
        }
    }
}

/// 一面的完整状态（纸 + 自定义纸图 + 笔迹 + 元素）。
/// 编辑中的「当前面」仍用 CardMakerView 既有的 paper/customPaperFile/strokes/elements 当工作副本，
/// 切面时靠 syncCurrentIntoPanels / loadPanel 与这里的存档换入换出，既有代码一律不动。
struct CardPanelState {
    var paper: PaperKind = .white
    var customPaperFile: String? = nil
    var strokes: [Stroke] = []
    var elements: [CardElement] = []
}

/// 帧动画的一帧（只活在编辑会话里，不落盘）：当前面的渲染快照 + 这一帧停留的秒数。
/// 时长在时间线上拖块的右边缘增减，保存卡片时随帧图一起落盘（见 CardDesign.frameDurations）。
struct FrameShot {
    var image: UIImage
    var duration: Double = 0.35
}

/// 时间线上的一个帧块：块宽 ∝ 停留时长（1 秒 = 110 pt，时长钳 0.1–2.0 秒）；
/// 点块 = 选中，拖块的右边缘把手 = 拉长/缩短这一帧。
private struct TimelineFrameBlock: View {
    let image: UIImage
    @Binding var duration: Double
    let isSelected: Bool
    let onSelect: () -> Void
    /// 本次拖拽开始时的时长（第一次 onChanged 时记下，之后按位移换算，避免累积漂移）
    @State private var dragStartDuration: Double? = nil

    /// 时间线刻度：1 秒对应的点数
    static let pointsPerSecond: CGFloat = 110
    static let minDuration: Double = 0.1
    static let maxDuration: Double = 2.0

    private var blockWidth: CGFloat {
        CGFloat(min(max(duration, Self.minDuration), Self.maxDuration)) * Self.pointsPerSecond
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: blockWidth, height: 64)
                .clipped()
            // 右边缘拖拽把手：半透明白条 + 三个小点；高优先级手势，避免被外层横向滚动抢走
            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(0.25))
                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 3, height: 3)
                    }
                }
            }
            .frame(width: 14)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStartDuration == nil { dragStartDuration = duration }
                        let start = dragStartDuration ?? duration
                        let delta = Double(value.translation.width) / Double(Self.pointsPerSecond)
                        duration = min(max(start + delta, Self.minDuration), Self.maxDuration)
                    }
                    .onEnded { _ in dragStartDuration = nil }
            )
        }
        .frame(width: blockWidth, height: 64)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}

struct CardMakerView: View {
    @EnvironmentObject var contactStore: ContactStore
    @EnvironmentObject var cardStore: CardStore
    let preselectedContactID: UUID?

    static let cardSize = CGSize(width: 330, height: 440)

    /// 站起来预览里纸往后躺的倾斜角：只加在纸组上（见 canvasSection）——绕 x 轴 +此角度，
    /// 顶边远离观众、底边靠前，纸面出现近大远小的透视；贴纸不做任何变换
    static let standFloorDegrees: Double = 55

    @State private var paper: PaperKind = .white
    @State private var customPaperFile: String? = nil
    @State private var paperPhotoItem: PhotosPickerItem? = nil
    @State private var showingPaperCamera = false
    /// 站起来预览：0 = 普通编辑，1 = 预览（纸往后躺下，贴纸原样不动）
    @State private var standPhase = 0
    @State private var packageKind: PackageKind = .none
    @State private var envelopeStyle: EnvelopeStyle = .cream
    @State private var boxStyle: BoxStyle = .purple
    @State private var packageDecorations: [PackageDecoration] = []
    @State private var selectedDecorationID: UUID? = nil
    @State private var packageCardImage: UIImage? = nil
    @State private var brush: BrushKind = .marker
    @State private var colorIndex: Int = 1
    @State private var strokes: [Stroke] = []
    @State private var currentPoints: [CGPoint] = []
    /// 画笔模式：开着时画布只收笔迹、元素手势锁定；点「完成」把笔迹转成可移动的图层元素
    @State private var isDrawingMode = false
    @State private var elements: [CardElement] = []
    @State private var selectedElementID: UUID? = nil
    @State private var cardName: String = ""
    @State private var assignTo: UUID? = nil
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var showingCamera = false
    /// 选好/拍好、准备做贴纸的照片先存这里，等 user 在确认框里选「抠图做贴纸」还是「直接用原图」；
    /// 任一选择或框关闭后清空，不留过期数据
    @State private var pendingPhotoData: Data? = nil
    @State private var showingPhotoUseChoice = false
    @State private var isProcessingPhoto = false
    @State private var showingTextSheet = false
    @State private var showingBubbleSheet = false
    @State private var showingStickerLibrary = false
    @State private var libraryStickers: [String] = []
    @State private var textDraft = ""
    @State private var bubbleDraft = ""
    @State private var showingClearConfirm = false
    @State private var savedMessage: String? = nil
    @State private var photoError: String? = nil
    /// 卡片形式与分面存档：panels 为空 = 一张纸模式（未初始化），当前面就是工作副本本身；
    /// 非空时 panels[currentPanel] 是当前面的存档副本，切面/保存前先同步（见 syncCurrentIntoPanels）
    @State private var cardFormat: CardFormat = .flat
    @State private var currentPanel: Int = 0
    @State private var panels: [CardPanelState] = []
    /// 帧动画（只活在编辑会话里）：拍一帧存一张当前面的渲染快照 + 停留时长，
    /// 在 frameSection 的一条时间线上拖右边缘改时长；保存卡片时才随卡落盘到 frames/（见 saveCard）
    @State private var frameShots: [FrameShot] = []
    /// 时间线上当前选中的帧（点块选中；删除按钮删的就是它）
    @State private var selectedFrameIndex: Int? = nil
    @State private var showingFramePlayer = false

    init(preselectedContactID: UUID? = nil) {
        self.preselectedContactID = preselectedContactID
        _assignTo = State(initialValue: preselectedContactID)
    }

    private var currentColor: RGBAColor { RGBAColor.palette[colorIndex] }

    private var selectedIndex: Int? {
        guard let id = selectedElementID else { return nil }
        return elements.firstIndex { $0.id == id }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                formatSection
                    .padding(12)
                    .modifier(ChunkyCard(fill: AppTheme.paper))
                    .padding(.horizontal, 12)
                canvasSection
                    .padding(12)
                    .modifier(ChunkyCard(fill: AppTheme.paper))
                    .padding(.horizontal, 12)
                templateSection
                    .padding(12)
                    .modifier(ChunkyCard(fill: AppTheme.paper))
                    .padding(.horizontal, 12)
                paperPicker
                    .padding(12)
                    .modifier(ChunkyCard(fill: AppTheme.paper))
                    .padding(.horizontal, 12)
                brushPicker
                    .padding(12)
                    .modifier(ChunkyCard(fill: AppTheme.paper))
                    .padding(.horizontal, 12)
                colorPicker
                    .padding(12)
                    .modifier(ChunkyCard(fill: AppTheme.paper))
                    .padding(.horizontal, 12)
                elementButtons
                    .padding(12)
                    .modifier(ChunkyCard(fill: AppTheme.paper))
                    .padding(.horizontal, 12)
                if let idx = selectedIndex {
                    selectedControls(index: idx)
                        .padding(12)
                        .modifier(ChunkyCard(fill: AppTheme.paper))
                        .padding(.horizontal, 12)
                }
                packageSection
                    .padding(12)
                    .modifier(ChunkyCard(fill: AppTheme.paper))
                    .padding(.horizontal, 12)
                frameSection
                    .padding(12)
                    .modifier(ChunkyCard(fill: AppTheme.paper))
                    .padding(.horizontal, 12)
                saveSection
                    .padding(12)
                    .modifier(ChunkyCard(fill: AppTheme.paper))
                    .padding(.horizontal, 12)
            }
            .padding()
        }
        .background(AppTheme.sunny)
        .navigationTitle(L("做卡片"))
        .toolbarBackground(AppTheme.sunny, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .onChange(of: photoItem) { _, newItem in
            guard let newItem = newItem else { return }
            Task { await processPhoto(newItem) }
        }
        .onChange(of: paperPhotoItem) { _, newItem in
            guard let newItem = newItem else { return }
            Task { await processPaperPhoto(newItem) }
        }
        .fullScreenCover(isPresented: $showingPaperCamera) {
            CameraPicker { image in
                applyPaperImage(image)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingTextSheet) {
            textSheet
        }
        .sheet(isPresented: $showingBubbleSheet) {
            bubbleSheet
        }
        .sheet(isPresented: $showingStickerLibrary) {
            stickerLibrarySheet
        }
        .fullScreenCover(isPresented: $showingFramePlayer) {
            FramePlayerView(images: frameShots.map { $0.image },
                            durations: frameShots.map { $0.duration })
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in
                if let data = image.jpegData(compressionQuality: 0.92) {
                    pendingPhotoData = data
                    // 相机封面紧接着要关，立刻弹确认框会被关闭过程吞掉，等它关完再弹
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        showingPhotoUseChoice = true
                    }
                } else {
                    photoError = L("没有读到这张照片，请换一张试试。")
                }
            }
            .ignoresSafeArea()
        }
        .alert(L("清空笔迹"), isPresented: $showingClearConfirm) {
            Button(L("取消"), role: .cancel) {}
            Button(L("清空"), role: .destructive) { strokes.removeAll() }
        } message: {
            Text(L("确定要清空所有笔迹吗？贴纸不会被清掉。"))
        }
        .alert(L("卡片库"), isPresented: Binding(
            get: { savedMessage != nil },
            set: { if !$0 { savedMessage = nil } }
        )) {
            Button(L("好")) { savedMessage = nil }
        } message: {
            Text(savedMessage ?? "")
        }
        .alert(L("照片贴纸"), isPresented: Binding(
            get: { photoError != nil },
            set: { if !$0 { photoError = nil } }
        )) {
            Button(L("好")) { photoError = nil }
        } message: {
            Text(photoError ?? "")
        }
        // 做贴纸前先问一句：抠图还是直接用原图——抠图偶尔会把主体削残（比如头被抠没），原图是兜底
        .confirmationDialog(L("这张照片怎么用？"), isPresented: $showingPhotoUseChoice, titleVisibility: .visible) {
            Button(L("抠图做贴纸")) {
                if let data = pendingPhotoData {
                    pendingPhotoData = nil
                    Task { await processPhotoData(data) }
                }
            }
            Button(L("直接用原图")) {
                if let data = pendingPhotoData {
                    pendingPhotoData = nil
                    Task { await processOriginalPhotoData(data) }
                }
            }
            Button(L("取消"), role: .cancel) { pendingPhotoData = nil }
        }
        .onChange(of: showingPhotoUseChoice) { _, isShowing in
            // 框以任何方式关掉都清掉待处理数据（按钮里已先取走要用的那份，这里只兜底）
            if !isShowing { pendingPhotoData = nil }
        }
    }

    /// 预览分层：贴纸（照片/emoji）是"主体"——预览中不随纸变换、原样浮在纸上方；
    /// 文字与画笔图层是印在纸上的内容，随纸组一起往后躺
    private func isSubjectSticker(_ element: CardElement) -> Bool {
        switch element.kind {
        case .photo, .emoji, .bubble: return true
        case .text, .drawing: return false
        }
    }

    /// 是否是对话气泡元素（翻转会把气泡里的字镜像成不可读，所以已选面板对气泡隐藏翻转）
    private func isBubble(_ element: CardElement) -> Bool {
        if case .bubble = element.kind { return true }
        return false
    }

    // 画布
    private var canvasSection: some View {
        ZStack(alignment: .topLeading) {
            // ── 纸组：纸 + 笔迹（预览时再加上印在纸上的文字/画笔图层）──
            // 站起来预览里只有这一组往后躺：绕 x 轴 +standFloorDegrees——y 向下的坐标系里，
            // 正角把顶边推向远离观众的方向、底边带向观众，纸面出现近大远小的透视，
            // 与保持原样的贴纸之间成约 90° 的立体关系。编辑时角度为 0（恒等变换），
            // 纸面渲染与从前完全一致。变换始终挂在这一组自己的视图上（不随分支增删），
            // standPhase 切换时 0 ↔ 55 由下方 animation 平滑插值。
            ZStack(alignment: .topLeading) {
                PaperBackgroundView(paper: paper, customFile: customPaperFile)
                StrokeRenderView(strokes: strokes + (currentPoints.isEmpty ? [] :
                    [Stroke(points: currentPoints, brush: brush, color: currentColor)]))
                if standPhase > 0 {
                    // 预览：纸面元素（文字/画笔图层）按原顺序原位置画进纸组，随纸一起躺下
                    ForEach($elements) { $element in
                        if !isSubjectSticker(element) {
                            EditorElementView(element: $element,
                                              isSelected: element.id == selectedElementID,
                                              onSelect: { selectedElementID = element.id },
                                              onDelete: { deleteElement(id: element.id) },
                                              standPreview: true)
                        }
                    }
                } else {
                    // 绘画捕捉层（在纸面与已渲染笔迹之上、元素之下）：只在画笔模式下接收触摸
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("cardCanvas"))
                                .onChanged { value in
                                    if currentPoints.isEmpty {
                                        currentPoints.append(value.startLocation)
                                    }
                                    if let last = currentPoints.last,
                                       hypot(value.location.x - last.x, value.location.y - last.y) > 2 {
                                        currentPoints.append(value.location)
                                    }
                                }
                                .onEnded { _ in
                                    if !currentPoints.isEmpty {
                                        strokes.append(Stroke(points: currentPoints, brush: brush, color: currentColor))
                                        currentPoints = []
                                    }
                                }
                        )
                        .allowsHitTesting(isDrawingMode)
                }
            }
            .rotation3DEffect(.degrees(standPhase > 0 ? Self.standFloorDegrees : 0),
                              axis: (x: 1, y: 0, z: 0),
                              anchor: .center,
                              perspective: 0.45)
            // ── 元素层 ──
            // 编辑时：全部元素按数组顺序叠放（原有渲染）。预览时：只剩主体贴纸（照片/emoji），
            // 它们保存的位置/大小/角度与编辑时完全一致——不做 3D 旋转、不缩放——浮在躺下的纸上方；
            // 唯一的位移是贴纸自己设的「悬浮」（平面内小幅晃动，编辑与预览中都有，见 EditorElementView）。
            // 画笔模式下元素锁定（不接收触摸，笔迹可以画过元素所在的位置）
            Group {
                if standPhase > 0 {
                    ForEach($elements) { $element in
                        if isSubjectSticker(element) {
                            EditorElementView(element: $element,
                                              isSelected: element.id == selectedElementID,
                                              onSelect: { selectedElementID = element.id },
                                              onDelete: { deleteElement(id: element.id) },
                                              standPreview: true)
                        }
                    }
                } else {
                    ForEach($elements) { $element in
                        EditorElementView(element: $element,
                                          isSelected: element.id == selectedElementID,
                                          onSelect: { selectedElementID = element.id },
                                          onDelete: { deleteElement(id: element.id) },
                                          standPreview: false)
                    }
                }
            }
            .allowsHitTesting(!isDrawingMode)
        }
        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.35)))
        .shadow(radius: 4)
        .coordinateSpace(.named("cardCanvas"))
        // 预览切换的 0.45 秒动画：驱动纸组躺下/放平的插值（变换本体在纸组上）；
        // 工具栏/面板在画布之外，不受任何变换影响
        .animation(.easeInOut(duration: 0.45), value: standPhase)
        .frame(maxWidth: .infinity)
    }

    /// 卡片形式选择（一张纸/对折打开/四折打开）+ 分面切换条（非一张纸时才出现）
    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("卡片形式")).font(.subheadline).bold()
            Picker(L("卡片形式"), selection: Binding(
                get: { cardFormat },
                set: { setFormat($0) }
            )) {
                ForEach(CardFormat.allCases, id: \.self) { f in
                    Text(L(f.rawValue)).tag(f)
                }
            }
            .pickerStyle(.segmented)
            if cardFormat != .flat {
                HStack(spacing: 8) {
                    ForEach(Array(cardFormat.panelNames.enumerated()), id: \.offset) { idx, name in
                        Button {
                            loadPanel(idx)
                        } label: {
                            Text(L(name))
                                .font(.subheadline)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(idx == currentPanel ? Color.accentColor : Color.secondary.opacity(0.15))
                                .foregroundStyle(idx == currentPanel ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// 把当前面的工作副本（paper/customPaperFile/strokes/elements）写回 panels[currentPanel]。
    /// 一张纸模式（panels 为空）或下标越界时什么都不做。
    private func syncCurrentIntoPanels() {
        guard panels.indices.contains(currentPanel) else { return }
        panels[currentPanel] = CardPanelState(paper: paper, customPaperFile: customPaperFile,
                                              strokes: strokes, elements: elements)
    }

    /// 切到第 idx 面：先把当前面同步回存档，再把目标面换入工作副本。
    /// 笔迹缓冲按面原样存（不强制转图层）；未落笔的 currentPoints 是瞬时状态，切面直接清掉。
    private func loadPanel(_ idx: Int) {
        guard panels.indices.contains(idx) else { return }
        syncCurrentIntoPanels()
        currentPanel = idx
        let p = panels[idx]
        paper = p.paper
        customPaperFile = p.customPaperFile
        strokes = p.strokes
        elements = p.elements
        selectedElementID = nil
        standPhase = 0
        isDrawingMode = false
        currentPoints = []
    }

    /// 换卡片形式。切回一张纸：分面存档整体丢弃，当前面的工作副本原样保留（不丢东西）。
    /// 换成对折/四折：第 0 面（封面）= 当前工作副本，其余面用同种纸开空面，从封面开始编辑。
    private func setFormat(_ f: CardFormat) {
        cardFormat = f
        if f == .flat {
            panels = []
            currentPanel = 0
            return
        }
        var newPanels: [CardPanelState] = [
            CardPanelState(paper: paper, customPaperFile: customPaperFile,
                           strokes: strokes, elements: elements)
        ]
        for _ in 1..<f.panelNames.count {
            newPanels.append(CardPanelState(paper: paper))
        }
        panels = newPanels
        currentPanel = 0
    }

    /// 预设模板：一键换纸 + 追加一组现成元素。只追加、不清空——已画的笔迹和已摆的元素都不动
    private var templateSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("模板")).font(.subheadline).bold()
            HStack(spacing: 10) {
                Button {
                    applyClassicTemplate()
                } label: {
                    Text(L("经典生日"))
                        .font(.subheadline)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Button {
                    applySakuraTemplate()
                } label: {
                    Text(L("樱花粉"))
                        .font(.subheadline)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Button {
                    applyMinimalTemplate()
                } label: {
                    Text(L("极简"))
                        .font(.subheadline)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func applyClassicTemplate() {
        paper = .cream
        customPaperFile = nil
        elements.append(contentsOf: [
            CardElement(kind: .text("生日快乐！", 34, RGBAColor.palette[1]), x: 165, y: 90),
            CardElement(kind: .emoji("🎂"), x: 165, y: 215, scale: 1.2),
            CardElement(kind: .emoji("🎈"), x: 72, y: 305),
            CardElement(kind: .emoji("🎈"), x: 258, y: 305, flipX: true)
        ])
    }

    private func applySakuraTemplate() {
        paper = .pink
        customPaperFile = nil
        elements.append(contentsOf: [
            CardElement(kind: .text("生日快乐", 30, RGBAColor.palette[7]), x: 165, y: 100),
            CardElement(kind: .emoji("🌸"), x: 60, y: 180),
            CardElement(kind: .emoji("🌸"), x: 270, y: 250),
            CardElement(kind: .emoji("🎀"), x: 165, y: 320)
        ])
    }

    private func applyMinimalTemplate() {
        paper = .white
        customPaperFile = nil
        elements.append(contentsOf: [
            CardElement(kind: .text("Happy Birthday", 26, RGBAColor.palette[0]), x: 165, y: 120),
            CardElement(kind: .emoji("✨"), x: 165, y: 230)
        ])
    }

    private var paperPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("纸张")).font(.subheadline).bold()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(PaperKind.allCases) { kind in
                        Button {
                            paper = kind
                            customPaperFile = nil   // 选回预设纸就不再用自定义纸图
                        } label: {
                            VStack(spacing: 4) {
                                PaperView(kind: kind)
                                    .frame(width: 40, height: 52)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .overlay(RoundedRectangle(cornerRadius: 4)
                                        .stroke(customPaperFile == nil && paper == kind ? Color.accentColor : Color.secondary.opacity(0.3),
                                                lineWidth: customPaperFile == nil && paper == kind ? 2.5 : 1))
                                Text(L(kind.rawValue)).font(.caption2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: 10) {
                PhotosPicker(selection: $paperPhotoItem, matching: .images) {
                    Label(L("相册选纸"), systemImage: "photo.on.rectangle")
                }
                Button {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        showingPaperCamera = true
                    } else {
                        photoError = L("这台设备没有可用的相机。")
                    }
                } label: {
                    Label(L("拍纸"), systemImage: "camera")
                }
                if customPaperFile != nil {
                    Text(L("自定义纸使用中")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var brushPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("画笔")).font(.subheadline).bold()
            HStack(spacing: 8) {
                ForEach(BrushKind.allCases) { kind in
                    Button {
                        brush = kind
                    } label: {
                        Text(L(kind.rawValue))
                            .font(.subheadline)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(brush == kind ? Color.accentColor : Color.secondary.opacity(0.15))
                            .foregroundStyle(brush == kind ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button {
                    if isDrawingMode {
                        finishDrawing()
                    } else {
                        isDrawingMode = true
                    }
                } label: {
                    Label(isDrawingMode ? L("完成") : L("画笔"),
                          systemImage: isDrawingMode ? "checkmark.circle.fill" : "pencil.tip.crop.circle")
                }
                Button {
                    if !strokes.isEmpty { _ = strokes.popLast() }
                } label: {
                    Label(L("撤销"), systemImage: "arrow.uturn.backward")
                }
                .disabled(strokes.isEmpty)
                Button(role: .destructive) {
                    showingClearConfirm = true
                } label: {
                    Label(L("清空"), systemImage: "trash")
                }
                .disabled(strokes.isEmpty)
            }
            if isDrawingMode {
                Text(L("在画布上作画，点「完成」后笔迹会变成可移动的图层。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("颜色")).font(.subheadline).bold()
            HStack(spacing: 8) {
                ForEach(Array(RGBAColor.palette.enumerated()), id: \.offset) { idx, rgba in
                    Button {
                        colorIndex = idx
                    } label: {
                        Circle()
                            .fill(rgba.color)
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(
                                colorIndex == idx ? Color.accentColor : Color.secondary.opacity(0.35),
                                lineWidth: colorIndex == idx ? 3 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var elementButtons: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("贴纸与文字")).font(.subheadline).bold()
            HStack(spacing: 10) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(isProcessingPhoto ? L("抠图中…") : L("相册选图"),
                          systemImage: "photo.on.rectangle.angled")
                }
                .disabled(isProcessingPhoto)
                Button {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        showingCamera = true
                    } else {
                        photoError = L("这台设备没有可用的相机。")
                    }
                } label: {
                    Label(L("拍照"), systemImage: "camera")
                }
                .disabled(isProcessingPhoto)
            }
            HStack(spacing: 10) {
                Button {
                    libraryStickers = FileStorage.stickerFileNames()
                    showingStickerLibrary = true
                } label: {
                    Label(L("我的贴纸"), systemImage: "square.grid.2x2")
                }
                Button {
                    textDraft = ""
                    showingTextSheet = true
                } label: {
                    Label(L("加祝福语"), systemImage: "text.badge.plus")
                }
                Button {
                    bubbleDraft = ""
                    showingBubbleSheet = true
                } label: {
                    Label(L("加气泡"), systemImage: "bubble.left")
                }
            }
            Text(L("点选元素后可拖动、双指缩放和旋转。"))
                .font(.caption).foregroundStyle(.secondary)
            Button {
                toggleStandPreview()
            } label: {
                Label(standPhase == 0 ? L("站起来预览") : L("结束预览"),
                      systemImage: standPhase == 0 ? "figure.stand" : "xmark.circle")
            }
            .disabled(!elements.contains { el in
                switch el.kind {
                case .photo, .emoji, .drawing, .bubble: return true
                case .text: return false
                }
            })
        }
    }

    private func selectedControls(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("已选元素")).font(.subheadline).bold()
            HStack(spacing: 14) {
                Button {
                    if index < elements.count - 1 {
                        elements.swapAt(index, index + 1)
                    }
                } label: { Label(L("上移一层"), systemImage: "square.3.layers.3d.top.filled") }
                Button {
                    if index > 0 {
                        elements.swapAt(index, index - 1)
                    }
                } label: { Label(L("下移一层"), systemImage: "square.3.layers.3d.bottom.filled") }
                Button {
                    duplicateElement(at: index)
                } label: { Label(L("复制"), systemImage: "doc.on.doc") }
                Button(role: .destructive) {
                    deleteElement(id: elements[index].id)
                } label: { Label(L("删除"), systemImage: "trash") }
            }
            if case .text(let content, _, let color) = elements[index].kind {
                TextField(L("祝福语"), text: Binding(
                    get: {
                        if case .text(let current, _, _) = elements[index].kind { return current }
                        return ""
                    },
                    set: { newContent in
                        if case .text(_, let size, let currentColor) = elements[index].kind {
                            elements[index].kind = .text(newContent, size, currentColor)
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                HStack {
                    Text(L("字号"))
                    Slider(value: Binding(
                        get: {
                            if case .text(_, let size, _) = elements[index].kind { return size }
                            return 28
                        },
                        set: { newSize in
                            elements[index].kind = .text(content, newSize, color)
                        }
                    ), in: 14...60, step: 1)
                }
            }
            if case .bubble = elements[index].kind {
                TextField(L("气泡里的话"), text: Binding(
                    get: {
                        if case .bubble(let current) = elements[index].kind { return current }
                        return ""
                    },
                    set: { newContent in
                        if case .bubble = elements[index].kind {
                            elements[index].kind = .bubble(newContent)
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
            }
            // 动态只给主体贴纸（照片/emoji）：文字与画笔图层是印在纸上的，不给这个开关
            if isSubjectSticker(elements[index]) {
                HStack {
                    Text(L("动态"))
                    Picker(L("动态"), selection: Binding(
                        get: { elements[index].motion },
                        set: { elements[index].motion = $0 }
                    )) {
                        Text(L("悬浮")).tag(StickerMotion.floating)
                        Text(L("不动")).tag(StickerMotion.still)
                    }
                    .pickerStyle(.segmented)
                }
                if elements[index].motion == .floating {
                    HStack {
                        Text(L("晃法"))
                        Picker(L("晃法"), selection: Binding(
                            get: { elements[index].floatPattern },
                            set: { elements[index].floatPattern = $0 }
                        )) {
                            ForEach(FloatPattern.allCases, id: \.self) { pattern in
                                Text(L(pattern.rawValue)).tag(pattern)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    HStack {
                        Text(L("幅度"))
                        Slider(value: Binding(
                            get: { Double(elements[index].floatAmplitude) },
                            set: { elements[index].floatAmplitude = CGFloat($0) }
                        ), in: 2...12, step: 1)
                        Text("\(Int(elements[index].floatAmplitude))")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(width: 22, alignment: .trailing)
                    }
                    Text(L("悬浮像小幽灵一样慢慢左右晃；不动就完全静止。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                // 翻转与透明度跟动态无关：悬浮或不动都可调。
                // 但气泡不给翻转：镜像会把气泡里的字翻成不可读（悬浮与透明度对气泡照常给）
                if !isBubble(elements[index]) {
                    HStack(spacing: 14) {
                        Button {
                            elements[index].flipX.toggle()
                        } label: { Label(L("翻转"), systemImage: "flip.horizontal") }
                        if elements[index].flipX {
                            Text(L("已翻转")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    Text(L("透明度"))
                    Slider(value: Binding(
                        get: { elements[index].opacity },
                        set: { elements[index].opacity = $0 }
                    ), in: 0.3...1.0, step: 0.05)
                    Text("\(Int(elements[index].opacity * 100))%")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// 按 id 删除一个元素并清掉选中：已选面板的删除按钮与元素右上角 ❌ 共用同一条路径
    private func deleteElement(id: UUID) {
        elements.removeAll { $0.id == id }
        if selectedElementID == id { selectedElementID = nil }
    }

    /// 复制选中的元素：新 UUID（结构体拷贝自动带上 kind/缩放/旋转/动态/晃法/幅度/翻转/透明度），
    /// 位置向右下错开 18pt 并钳在画布内，插在原件正后方，选中复制品方便接着拖走
    private func duplicateElement(at index: Int) {
        guard elements.indices.contains(index) else { return }
        let original = elements[index]
        var copy = original
        copy.id = UUID()
        copy.x = min(max(original.x + 18, 0), Self.cardSize.width)
        copy.y = min(max(original.y + 18, 0), Self.cardSize.height)
        elements.insert(copy, at: index + 1)
        selectedElementID = copy.id
    }

    private let decorationPalette = ["🎈", "🎀", "⭐️", "🌸", "💛", "✨",
                                       "🦋", "🕊️", "🍓", "🎁", "🌹", "☀️"]

    /// 包装步骤：选信封/礼盒与样式，再往包装上挂装饰
    private var packageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("包装")).font(.subheadline).bold()
            Picker(L("包装"), selection: $packageKind) {
                ForEach(PackageKind.allCases) { kind in
                    Text(L(kind.rawValue)).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: packageKind) { _, _ in refreshPackageCardImage() }

            if packageKind == .envelope {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(EnvelopeStyle.allCases) { style in
                            Button {
                                envelopeStyle = style
                            } label: {
                                VStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(style.color)
                                        .frame(width: 46, height: 32)
                                        .overlay(RoundedRectangle(cornerRadius: 4)
                                            .stroke(envelopeStyle == style ? Color.accentColor : Color.secondary.opacity(0.3),
                                                    lineWidth: envelopeStyle == style ? 2.5 : 1))
                                    Text(L(style.rawValue)).font(.caption2)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if packageKind == .box {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(BoxStyle.allCases) { style in
                            Button {
                                boxStyle = style
                            } label: {
                                VStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(style.color)
                                        .frame(width: 46, height: 32)
                                        .overlay(RoundedRectangle(cornerRadius: 4)
                                            .stroke(boxStyle == style ? Color.accentColor : Color.secondary.opacity(0.3),
                                                    lineWidth: boxStyle == style ? 2.5 : 1))
                                    Text(L(style.rawValue)).font(.caption2)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if packageKind != .none {
                ZStack {
                    PackageStageView(kind: packageKind,
                                     envelopeStyle: envelopeStyle,
                                     boxStyle: boxStyle,
                                     cardImage: packageCardImage,
                                     decorations: packageDecorations)
                    ForEach($packageDecorations) { $deco in
                        DecorationHandleView(deco: $deco,
                                             isSelected: deco.id == selectedDecorationID,
                                             onSelect: { selectedDecorationID = deco.id })
                    }
                }
                .frame(width: PackageStageView.stageSize, height: PackageStageView.stageSize)
                .background(Color.secondary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .coordinateSpace(.named("packageStage"))
                .frame(maxWidth: .infinity)
                .onAppear { refreshPackageCardImage() }

                Text(L("点下面的装饰把它挂到包装上，拖动可以挪位置，点中后可以删除。"))
                    .font(.caption).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(decorationPalette, id: \.self) { symbol in
                            Button {
                                addPackageDecoration(symbol)
                            } label: {
                                Text(symbol).font(.title2)
                                    .frame(width: 40, height: 40)
                                    .background(Color.secondary.opacity(0.10))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack(spacing: 14) {
                    Button {
                        refreshPackageCardImage()
                    } label: {
                        Label(L("刷新预览"), systemImage: "arrow.clockwise")
                    }
                    if let sel = selectedDecorationID,
                       packageDecorations.contains(where: { $0.id == sel }) {
                        Button(role: .destructive) {
                            packageDecorations.removeAll { $0.id == sel }
                            selectedDecorationID = nil
                        } label: {
                            Label(L("删除装饰"), systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func addPackageDecoration(_ symbol: String) {
        let deco = PackageDecoration(emoji: symbol, x: 150, y: 210)
        packageDecorations.append(deco)
        selectedDecorationID = deco.id
    }

    /// 把当前画布渲染成小图，放进包装台面里当"探出头的卡片"。
    /// 多面形式时先同步当前面，再渲染整张打开的拼版，让包装预览里看到的是整张卡。
    private func refreshPackageCardImage() {
        guard packageKind != .none else { return }
        if cardFormat != .flat && !panels.isEmpty {
            syncCurrentIntoPanels()
            let renderer = ImageRenderer(content: CardSheetView(panels: panels, format: cardFormat))
            renderer.scale = 2
            packageCardImage = renderer.uiImage
            return
        }
        let content = CardContentView(paper: paper, customPaperFile: customPaperFile,
                                      strokes: strokes,
                                      elements: elements, size: Self.cardSize)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        packageCardImage = renderer.uiImage
    }

    /// 帧动画区：摆好画面拍一帧、挪一挪贴纸再拍一帧。所有帧排在一条时间线上，
    /// 块越宽停留越久；点块选中，拖块的右边缘拉长/缩短这一帧，选中后可整帧删除；
    /// 帧先只存在内存里，点保存时随卡片一起落盘
    private var frameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("帧动画")).font(.subheadline).bold()
            HStack(spacing: 10) {
                Button {
                    captureFrame()
                } label: {
                    Label(L("拍一帧"), systemImage: "camera")
                }
                .buttonStyle(.bordered)
                Button {
                    showingFramePlayer = true
                } label: {
                    Label(L("播放"), systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
                .disabled(frameShots.isEmpty)
                if let sel = selectedFrameIndex, frameShots.indices.contains(sel) {
                    Button(role: .destructive) {
                        frameShots.remove(at: sel)
                        selectedFrameIndex = nil
                    } label: {
                        Label(L("删除这一帧"), systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
            if !frameShots.isEmpty {
                Text(String(format: L("共 %d 帧"), frameShots.count) + " · "
                     + String(format: L("总时长 %.1f 秒"),
                              frameShots.reduce(0) { $0 + $1.duration }))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        ForEach(frameShots.indices, id: \.self) { idx in
                            TimelineFrameBlock(
                                image: frameShots[idx].image,
                                duration: Binding(
                                    get: {
                                        frameShots.indices.contains(idx) ? frameShots[idx].duration : 0.35
                                    },
                                    set: { newDuration in
                                        if frameShots.indices.contains(idx) {
                                            frameShots[idx].duration = newDuration
                                        }
                                    }
                                ),
                                isSelected: selectedFrameIndex == idx,
                                onSelect: { selectedFrameIndex = idx }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                Text(L("点一帧选中，拖它的右边缘拉长或缩短"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 拍一帧：把当前面渲染成一张快照存进帧列（笔迹先转图层，守卫与 saveCard 同款，
    /// 保证帧里看到的和画布上一模一样）。注意：多面形式下拍的只是当前面，
    /// 整张拼版是保存卡片时才做的——这是定版时接受的简化。
    private func captureFrame() {
        if !strokes.isEmpty {
            _ = convertStrokesToElement()
            isDrawingMode = false
        }
        let content = CardContentView(paper: paper, customPaperFile: customPaperFile,
                                      strokes: strokes,
                                      elements: elements, size: Self.cardSize)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        if let img = renderer.uiImage {
            frameShots.append(FrameShot(image: img))
        }
    }

    private var saveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("保存卡片")).font(.subheadline).bold()
            TextField(L("卡片名称（可不填）"), text: $cardName)
                .textFieldStyle(.roundedBorder)
            Picker(L("送给（卡片池）"), selection: $assignTo) {
                Text(L("不指定")).tag(UUID?.none)
                ForEach(contactStore.contacts) { contact in
                    Text(contact.name).tag(UUID?.some(contact.id))
                }
            }
            Button {
                saveCard()
            } label: {
                Label(L("保存到卡片库"), systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SunnyButtonStyle())
        }
    }

    private var textSheet: some View {
        NavigationStack {
            VStack(spacing: 14) {
                TextField(L("写一句祝福语，如：生日快乐！"), text: $textDraft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                Text(textDraft.isEmpty ? L("生日快乐！") : textDraft)
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .foregroundStyle(currentColor.color)
                Spacer()
            }
            .padding()
            .navigationTitle(L("加祝福语"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("取消")) { showingTextSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("添加")) {
                        let content = textDraft.isEmpty ? L("生日快乐！") : textDraft
                        addElement(.text(content, 28, currentColor))
                        showingTextSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// 加对话气泡：话写进气泡里、看得见（普通卡存成静态图，气泡里的字必须直接可见）
    private var bubbleSheet: some View {
        NavigationStack {
            VStack(spacing: 14) {
                TextField(L("气泡里的话"), text: $bubbleDraft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                SpeechBubbleView(message: bubbleDraft.isEmpty ? L("生日快乐！") : bubbleDraft)
                Spacer()
            }
            .padding()
            .navigationTitle(L("加气泡"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("取消")) { showingBubbleSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("添加")) {
                        let content = bubbleDraft.isEmpty ? L("生日快乐！") : bubbleDraft
                        addElement(.bubble(content))
                        showingBubbleSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// 我的贴纸库：以前抠好的贴纸都在这里，点一张就贴到当前卡片上
    private var stickerLibrarySheet: some View {
        NavigationStack {
            Group {
                if libraryStickers.isEmpty {
                    ContentUnavailableView(L("还没有贴纸"),
                                           systemImage: "square.grid.2x2",
                                           description: Text(L("先用「照片做贴纸」抠一张，做好后会出现在这里，以后做新卡可以直接选。")))
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                            ForEach(libraryStickers, id: \.self) { fileName in
                                Button {
                                    addElement(.photo(fileName))
                                    showingStickerLibrary = false
                                } label: {
                                    if let img = FileStorage.loadImage(fileName: fileName, subdir: "stickers") {
                                        Image(uiImage: img)
                                            .resizable().scaledToFit()
                                            .frame(width: 96, height: 96)
                                            .background(Color.secondary.opacity(0.08))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    } else {
                                        Image(systemName: "photo")
                                            .frame(width: 96, height: 96)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(L("我的贴纸"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("关闭")) { showingStickerLibrary = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func addElement(_ kind: ElementKind) {
        let element = CardElement(kind: kind,
                                  x: Self.cardSize.width / 2,
                                  y: Self.cardSize.height / 2)
        elements.append(element)
        selectedElementID = element.id
    }

    private func processPhoto(_ item: PhotosPickerItem) async {
        defer {
            photoItem = nil   // 清空选择，否则再选同一张照片不会触发
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                photoError = L("没有读到这张照片，请换一张试试。")
                return
            }
            // 先不抠：存下数据、弹确认框，让 user 选抠图还是直接用原图
            pendingPhotoData = data
            showingPhotoUseChoice = true
        } catch {
            photoError = String(format: L("读取照片失败：%@"), error.localizedDescription)
        }
    }

    /// 相册和相机共用：拿到照片数据后抠图做成贴纸，贴到当前卡片上
    private func processPhotoData(_ data: Data) async {
        isProcessingPhoto = true
        defer { isProcessingPhoto = false }
        let fileName = await Task.detached(priority: .userInitiated) {
            CutoutHelper.makeStickerPNG(from: data)
        }.value
        if let fileName = fileName {
            addElement(.photo(fileName))
        } else {
            photoError = L("这张照片抠图失败（可能没识别到清晰的主体），请换一张主体清楚的照片。")
        }
    }

    /// 直接用原图做贴纸（抠图的兜底）：不抠图，整张长方形照片贴到当前卡片上，
    /// 存法与抠图贴纸完全一致（stickers/ + sticker-<UUID>.png），也会进「我的贴纸」
    private func processOriginalPhotoData(_ data: Data) async {
        isProcessingPhoto = true
        defer { isProcessingPhoto = false }
        let fileName = await Task.detached(priority: .userInitiated) {
            CutoutHelper.makeOriginalPNG(from: data)
        }.value
        if let fileName = fileName {
            addElement(.photo(fileName))
        } else {
            photoError = L("这张照片处理失败，请换一张试试。")
        }
    }

    /// 相册选纸：读出照片后当纸面用（不抠图，整张铺满）
    private func processPaperPhoto(_ item: PhotosPickerItem) async {
        defer { paperPhotoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                photoError = L("没有读到这张照片，请换一张试试。")
                return
            }
            applyPaperImage(image)
        } catch {
            photoError = String(format: L("读取照片失败：%@"), error.localizedDescription)
        }
    }

    private func applyPaperImage(_ image: UIImage) {
        guard let fileName = PaperImageHelper.saveAsPaper(image) else {
            photoError = L("这张照片处理失败，请换一张试试。")
            return
        }
        if let old = customPaperFile, old != fileName {
            FileStorage.deleteFile(fileName: old, subdir: "papers")
        }
        customPaperFile = fileName
    }

    /// 进入/退出站起来预览：进入时纸组用 0.45 秒往后躺下（+55° 透视），贴纸原样不动；
    /// 退出时纸组转回 0° 放平，回到普通编辑
    private func toggleStandPreview() {
        if standPhase == 0 {
            isDrawingMode = false   // 预览与画笔模式互斥，进预览先退出画笔模式
            standPhase = 1
        } else {
            standPhase = 0
        }
    }

    /// 把笔迹缓冲整体转成一个透明底 PNG 图层元素：之后能像贴纸一样拖动/缩放/旋转/删除/调层。
    /// 转换失败（渲染或写盘出错）时返回 false 并保留笔迹缓冲，画过的东西不会丢。
    @discardableResult
    private func convertStrokesToElement() -> Bool {
        guard !strokes.isEmpty else { return false }
        let content = StrokeRenderView(strokes: strokes)
            .frame(width: Self.cardSize.width, height: Self.cardSize.height)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        renderer.isOpaque = false   // 只要笔迹本身，背景必须透明
        guard let uiImage = renderer.uiImage, let png = uiImage.pngData() else { return false }
        let fileName = "draw-\(UUID().uuidString).png"
        do {
            try png.write(to: FileStorage.url(for: fileName, subdir: "drawings"))
        } catch {
            return false
        }
        addElement(.drawing(fileName))
        strokes.removeAll()
        currentPoints = []
        return true
    }

    /// 画笔模式点「完成」：笔迹转图层，然后退出画笔模式
    private func finishDrawing() {
        _ = convertStrokesToElement()
        isDrawingMode = false
    }

    private func saveCard() {
        // 笔迹缓冲里还有没转图层的笔迹就先转：保存出来的卡和编辑器里看到的一模一样，
        // 且笔迹以图层元素身份进成品渲染，不再是散落在背景上的一层
        if !strokes.isEmpty {
            _ = convertStrokesToElement()
            isDrawingMode = false
        }
        // 渲染：一张纸走原来的单面渲染；多面先把当前面同步回存档，
        // 再把整张纸打开拼版渲染成一张 PNG（对折 660×440、四折 660×880，均 scale 3）
        let uiImage: UIImage?
        if cardFormat != .flat && !panels.isEmpty {
            syncCurrentIntoPanels()
            let renderer = ImageRenderer(content: CardSheetView(panels: panels, format: cardFormat))
            renderer.scale = 3
            uiImage = renderer.uiImage
        } else {
            let content = CardContentView(paper: paper, customPaperFile: customPaperFile,
                                          strokes: strokes,
                                          elements: elements, size: Self.cardSize)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 3
            uiImage = renderer.uiImage
        }
        guard let uiImage = uiImage, let png = uiImage.pngData() else {
            savedMessage = L("保存失败，请再试一次。")
            return
        }
        let fileName = "card-\(UUID().uuidString).png"
        let url = FileStorage.url(for: fileName, subdir: "cards")
        do {
            try png.write(to: url)
        } catch {
            savedMessage = String(format: L("保存失败：%@"), error.localizedDescription)
            return
        }
        // 帧动画落盘：先定这张卡的 id，帧图按 frame-<卡id>-<序号>.png 写进 frames/；
        // 某一帧写失败只跳过那一帧（它的时长也一起跳过，文件名与时长始终逐项对齐），
        // 不连累整张卡的保存；没拍帧时这里什么都不做
        let cardID = UUID()
        var frameNames: [String] = []
        var savedDurations: [Double] = []
        for (idx, shot) in frameShots.enumerated() {
            guard let data = shot.image.pngData() else { continue }
            let frameName = "frame-\(cardID.uuidString)-\(idx).png"
            do {
                try data.write(to: FileStorage.url(for: frameName, subdir: "frames"))
                frameNames.append(frameName)
                savedDurations.append(shot.duration)
            } catch {
                continue
            }
        }
        let name = cardName.trimmingCharacters(in: .whitespaces).isEmpty
            ? String(format: L("我的卡片 %@"), Self.dateLabel())
            : cardName
        // 归属以"联系人还存在"为准：在别的页面被删掉的联系人不写悬空 ID
        let target = assignTo.flatMap { contactStore.contact(id: $0) }
        let card = CardDesign(id: cardID, name: name, imageFile: fileName, assignedContactID: target?.id,
                              packageKind: packageKind == .none ? nil : packageKind.rawValue,
                              packageStyle: packageKind == .envelope ? envelopeStyle.rawValue
                                            : packageKind == .box ? boxStyle.rawValue : nil,
                              decorations: packageDecorations.isEmpty ? nil : packageDecorations,
                              frameFiles: frameNames,
                              frameDurations: savedDurations)
        guard cardStore.add(card) else {
            // 元数据落盘失败：删掉刚写的图片，不留孤儿文件，也不误报成功
            try? FileManager.default.removeItem(at: url)
            for frameName in frameNames {
                FileStorage.deleteFile(fileName: frameName, subdir: "frames")
            }
            savedMessage = L("保存失败（存储空间可能不足），请再试一次。")
            return
        }
        if var contact = target {
            if !contact.cardPoolIDs.contains(card.id) {
                contact.cardPoolIDs.append(card.id)
                contactStore.update(contact)
            }
        }
        savedMessage = String(format: L("已保存「%@」到卡片库。"), name)
    }

    private static func dateLabel() -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: Date())
    }
}

/// 包装台面（300×300）：卡片从信封/礼盒里探出头，装饰挂在包装外面。
/// 这里只负责静态展示；做卡时的拖动由外层 DecorationHandleView 叠着处理。
struct PackageStageView: View {
    let kind: PackageKind
    let envelopeStyle: EnvelopeStyle
    let boxStyle: BoxStyle
    let cardImage: UIImage?
    let decorations: [PackageDecoration]

    static let stageSize: CGFloat = 300

    var body: some View {
        ZStack {
            if kind != .none, let img = cardImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 128, height: 171)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(radius: 3)
                    .offset(y: kind == .envelope ? -50 : -56)
            }
            switch kind {
            case .envelope: envelopeBody
            case .box: boxBody
            case .none: EmptyView()
            }
            ForEach(decorations) { deco in
                Text(deco.emoji)
                    .font(.system(size: 30 * deco.scale))
                    .rotationEffect(.degrees(deco.rotation))
                    .position(x: deco.x, y: deco.y)
            }
        }
        .frame(width: Self.stageSize, height: Self.stageSize)
    }

    private var envelopeBody: some View {
        let base = envelopeStyle.color
        return ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(base)
                .frame(width: 280, height: 180)
                .shadow(radius: 4)
            // 封口折线（信封口的两条斜边）
            Path { p in
                p.move(to: CGPoint(x: 4, y: 2))
                p.addLine(to: CGPoint(x: 140, y: 82))
                p.addLine(to: CGPoint(x: 276, y: 2))
            }
            .stroke(Color.white.opacity(0.45), lineWidth: 2)
            .frame(width: 280, height: 180)
            // 下半部兜的压暗，做出兜的层次
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.06))
                .frame(width: 280, height: 104)
                .offset(y: 38)
        }
        .offset(y: 36)
    }

    private var boxBody: some View {
        let base = boxStyle.color
        let ribbon = Color(red: 0.98, green: 0.94, blue: 0.82)
        return ZStack {
            // 盒身
            RoundedRectangle(cornerRadius: 8)
                .fill(base)
                .frame(width: 250, height: 165)
                .shadow(radius: 4)
                .offset(y: 40)
            // 盒身上的竖丝带
            Rectangle()
                .fill(ribbon)
                .frame(width: 26, height: 165)
                .offset(y: 40)
            // 盒盖（比盒身略宽）
            RoundedRectangle(cornerRadius: 8)
                .fill(base.opacity(0.88))
                .frame(width: 268, height: 46)
                .shadow(radius: 3)
                .offset(y: -42)
            // 盒盖上的竖丝带
            Rectangle()
                .fill(ribbon)
                .frame(width: 26, height: 46)
                .offset(y: -42)
            // 蝴蝶结
            Text("🎀")
                .font(.system(size: 36))
                .offset(y: -72)
        }
    }
}

/// 做卡时叠在包装台面上的拖动把手：透明，只在选中时画圈，负责拖动装饰
struct DecorationHandleView: View {
    @Binding var deco: PackageDecoration
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var dragStart: CGPoint? = nil

    var body: some View {
        Color.clear
            .frame(width: 54, height: 54)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .position(x: deco.x, y: deco.y)
            .onTapGesture { onSelect() }
            .gesture(
                DragGesture(coordinateSpace: .named("packageStage"))
                    .onChanged { value in
                        if dragStart == nil { dragStart = CGPoint(x: deco.x, y: deco.y) }
                        let rawX = (dragStart?.x ?? CGFloat(deco.x)) + value.translation.width
                        let rawY = (dragStart?.y ?? CGFloat(deco.y)) + value.translation.height
                        deco.x = Double(min(max(rawX, 14), 286))
                        deco.y = Double(min(max(rawY, 14), 286))
                        onSelect()
                    }
                    .onEnded { _ in dragStart = nil }
            )
    }
}

/// 动画信的画面文件存取：图压到长边 1200 存 JPEG，视频原样存到 letters/
enum LetterMediaHelper {
    static func saveImage(_ image: UIImage) -> String? {
        let maxSide: CGFloat = 1200
        let size = image.size
        let longest = max(size.width, size.height)
        var target = size
        if longest > maxSide {
            let ratio = maxSide / longest
            target = CGSize(width: size.width * ratio, height: size.height * ratio)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let data = scaled.jpegData(compressionQuality: 0.85) else { return nil }
        let fileName = "media-\(UUID().uuidString).jpg"
        do {
            try data.write(to: FileStorage.url(for: fileName, subdir: "letters"))
            return fileName
        } catch { return nil }
    }

    static func saveVideoData(_ data: Data) -> String? {
        let fileName = "video-\(UUID().uuidString).mov"
        do {
            try data.write(to: FileStorage.url(for: fileName, subdir: "letters"))
            return fileName
        } catch { return nil }
    }
}

/// 动画信在卡片库里显示的封面海报（静态）：纸面 + 走路贴纸 + 完整开场白
struct LetterPosterView: View {
    let data: LetterTemplateData

    var body: some View {
        ZStack {
            PaperView(kind: .cream)
            VStack(spacing: 16) {
                Spacer()
                walkerView.frame(height: 110)
                Text(data.titleText)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("💌")
                    .font(.system(size: 40))
                Spacer()
            }
            .padding(24)
            // 海报上标出圆点的位置（海报历来不画其他固定贴纸，这里只补圆点，让封面看得出哪里有点可点）
            ForEach(data.fixedStickers.filter { $0.isDot }) { dot in
                LetterDotView()
                    .position(x: dot.x * 330, y: dot.y * 440)
            }
        }
        .frame(width: 330, height: 440)
    }

    @ViewBuilder
    private var walkerView: some View {
        if data.walkerKind == "photo", let v = data.walkerValue,
           let img = FileStorage.loadImage(fileName: v, subdir: "stickers") {
            Image(uiImage: img).resizable().scaledToFit()
        } else if data.walkerKind == "emoji", let v = data.walkerValue {
            Text(v).font(.system(size: 84))
        } else {
            Text("🎂").font(.system(size: 84))
        }
    }
}

/// 动画信里的一段视频画面：出现就播，离开就停
struct LetterVideoView: View {
    let url: URL
    @State private var player: AVPlayer? = nil

    var body: some View {
        Group {
            if let player = player {
                VideoPlayer(player: player)
            } else {
                Color.black
            }
        }
        .onAppear {
            if player == nil {
                let p = AVPlayer(url: url)
                player = p
                p.play()
            } else {
                player?.play()
            }
        }
        .onDisappear { player?.pause() }
    }
}

/// 动画信播放器：开场白每 0.5 秒出一个字，走路贴纸随字走过，
/// 固定贴纸到点出现后不消失（点开看回忆），字打完后信的内容淡入
struct LetterPlayerView: View {
    let data: LetterTemplateData
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var runID = 0
    @State private var memorySticker: LetterFixedSticker? = nil
    @State private var shareURL: URL? = nil
    @State private var showingShare = false
    @State private var isExporting = false
    @State private var exportFailed = false

    private var titleChars: [Character] { Array(data.titleText) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let f = data.topMediaFile {
                        mediaView(file: f, isVideo: data.topMediaIsVideo)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    stage
                    if step >= titleChars.count && !data.letterText.isEmpty {
                        Text(data.letterText)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(Color(red: 0.98, green: 0.95, blue: 0.87))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if step >= titleChars.count {
                        Text(L("点贴纸可以打开里面的回忆"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let f = data.bottomMediaFile {
                        mediaView(file: f, isVideo: data.bottomMediaIsVideo)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Button {
                        runID += 1
                    } label: {
                        Label(L("重播"), systemImage: "arrow.clockwise")
                    }
                    .padding(.top, 4)
                }
                .padding()
            }
            .navigationTitle(L("动画信"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("关闭")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            doExportVideo()
                        } label: {
                            Label(L("导出视频"), systemImage: "film")
                        }
                        Button {
                            doExportHTML()
                        } label: {
                            Label(L("导出网页（可点贴纸）"), systemImage: "safari")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(isExporting)
                }
            }
            .sheet(item: $memorySticker) { sticker in
                LetterMemoryView(sticker: sticker)
            }
            .sheet(isPresented: $showingShare) {
                if let shareURL = shareURL {
                    ActivityShareSheet(items: [shareURL])
                }
            }
            .alert(L("提示"), isPresented: $exportFailed) {
                Button(L("好")) { exportFailed = false }
            } message: {
                Text(L("生成失败，请再试一次。"))
            }
            .overlay {
                if isExporting {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        ProgressView(L("正在生成…"))
                            .padding()
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .task(id: runID) {
            step = 0
            while step < titleChars.count {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { return }
                step += 1
            }
        }
    }

    /// 导出成 MP4：对方在任何手机上点开就能播（贴纸不可点）
    private func doExportVideo() {
        isExporting = true
        Task {
            let url = await LetterVideoExporter.exportMP4(data: data)
            isExporting = false
            if let url = url {
                shareURL = url
                showingShare = true
            } else {
                exportFailed = true
            }
        }
    }

    /// 导出成单个 HTML 网页文件：对方用浏览器打开就能播，固定贴纸可点开回忆
    private func doExportHTML() {
        isExporting = true
        Task.detached {
            let url = LetterHTMLExporter.exportHTML(data: data)
            await MainActor.run {
                isExporting = false
                if let url = url {
                    shareURL = url
                    showingShare = true
                } else {
                    exportFailed = true
                }
            }
        }
    }

    private func mediaView(file: String, isVideo: Bool) -> some View {
        let url = FileStorage.url(for: file, subdir: "letters")
        return Group {
            if isVideo {
                LetterVideoView(url: url)
            } else if let img = FileStorage.loadImage(fileName: file, subdir: "letters") {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Color.secondary.opacity(0.15)
            }
        }
    }

    private var stage: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Text(String(titleChars.prefix(step)))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .frame(width: geo.size.width, alignment: .center)
                    .padding(.top, 6)
                walkerView
                    .position(x: walkerX(in: geo.size.width), y: 96)
                ForEach(data.fixedStickers) { sticker in
                    if step >= sticker.appearAtStep {
                        fixedStickerView(sticker)
                            .position(x: sticker.x * geo.size.width,
                                      y: sticker.y * geo.size.height)
                            .onTapGesture {
                                if sticker.memoryText != nil || sticker.memoryImageFile != nil {
                                    memorySticker = sticker
                                }
                            }
                    }
                }
            }
        }
        .frame(height: 300)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func walkerX(in width: CGFloat) -> CGFloat {
        guard !titleChars.isEmpty else { return width / 2 }
        let progress = Double(step) / Double(titleChars.count)
        return 34 + (width - 68) * progress
    }

    @ViewBuilder
    private var walkerView: some View {
        if data.walkerKind == "photo", let v = data.walkerValue,
           let img = FileStorage.loadImage(fileName: v, subdir: "stickers") {
            Image(uiImage: img).resizable().scaledToFit().frame(width: 62, height: 62)
        } else if data.walkerKind == "emoji", let v = data.walkerValue {
            Text(v).font(.system(size: 48))
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func fixedStickerView(_ sticker: LetterFixedSticker) -> some View {
        if sticker.isDot {
            // 圆点：点它打开回忆页，藏着的话就在那里（与固定贴纸同一套点开机制）
            LetterDotView()
        } else if sticker.kind == "photo",
           let img = FileStorage.loadImage(fileName: sticker.value, subdir: "stickers") {
            Image(uiImage: img).resizable().scaledToFit().frame(width: 56, height: 56)
        } else {
            Text(sticker.value).font(.system(size: 42))
        }
    }
}

/// 点开固定贴纸看到的回忆页（照片 + 文字）
struct LetterMemoryView: View {
    let sticker: LetterFixedSticker
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let f = sticker.memoryImageFile,
                       let img = FileStorage.loadImage(fileName: f, subdir: "letters") {
                        Image(uiImage: img).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if let t = sticker.memoryText, !t.isEmpty {
                        Text(t).font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .navigationTitle(L("回忆"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("关闭")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// 动画信里的圆点（bullet point）：播放器、海报、编辑器把手与列表缩略图共用同一个样子——
/// 主色填充小圆 + 白圈，点它打开回忆页看藏着的话
struct LetterDotView: View {
    var size: CGFloat = 26

    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
    }
}

/// 编辑动画信时拖固定贴纸位置的把手：贴纸画在把手上，拖动改相对坐标
struct LetterFixedHandle: View {
    @Binding var sticker: LetterFixedSticker
    let stageSize: CGSize

    var body: some View {
        Color.clear
            .frame(width: 58, height: 58)
            .contentShape(Rectangle())
            .overlay {
                if sticker.isDot {
                    LetterDotView()
                } else if sticker.kind == "photo",
                   let img = FileStorage.loadImage(fileName: sticker.value, subdir: "stickers") {
                    Image(uiImage: img).resizable().scaledToFit().frame(width: 48, height: 48)
                } else {
                    Text(sticker.value).font(.system(size: 36))
                }
            }
            .position(x: sticker.x * stageSize.width, y: sticker.y * stageSize.height)
            .gesture(
                DragGesture(coordinateSpace: .named("letterStageEdit"))
                    .onChanged { v in
                        sticker.x = min(max(Double(v.location.x / stageSize.width), 0.06), 0.94)
                        sticker.y = min(max(Double(v.location.y / stageSize.height), 0.06), 0.94)
                    }
            )
    }
}

/// 动画信编辑器：开场白 + 信 + 上下画面（图/视频）+ 走路贴纸 + 固定贴纸（位置/出现时机/回忆）
/// 旅程地图的画面文件存取：重绘一次把 EXIF 方向摆正、压长边、存 PNG 到 journeys/
/// （与抠图原图贴纸 CutoutHelper.makeOriginalPNG 同一套做法，只是目录与前缀不同）
enum JourneyMediaHelper {
    static func saveImage(data: Data, prefix: String, maxSide: CGFloat) -> String? {
        guard let source = UIImage(data: data) else { return nil }
        let size = source.size
        let longest = max(size.width, size.height)
        var target = size
        if longest > maxSide {
            let ratio = maxSide / longest
            target = CGSize(width: size.width * ratio, height: size.height * ratio)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let normalized = renderer.image { _ in
            source.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let png = normalized.pngData() else { return nil }
        let fileName = "\(prefix)\(UUID().uuidString).png"
        do {
            try png.write(to: FileStorage.url(for: fileName, subdir: "journeys"))
            return fileName
        } catch {
            return nil
        }
    }
}

/// 旅程站点的录音 / 播放引擎（精简版，不带转写）：录音存 Documents/journeys/voice-<UUID>.m4a，
/// 录完只通过 onSaved 回调把文件名交回界面写进对应站点；播放供编辑器与站点内容页共用。
/// 麦克风授权在流程内请求，失败只给中文提示，不崩溃。
final class JourneyVoiceRecorder: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var isPlaying = false
    @Published var statusText: String? = nil

    /// 录音停止并落盘后回调（参数为新文件名）
    var onSaved: ((String) -> Void)?

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var recordingFileName: String?

    // 录音

    func startRecording() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            beginRecording()
        case .denied:
            statusText = L("没有麦克风权限，无法录音。")
        case .undetermined:
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.beginRecording()
                    } else {
                        self?.statusText = L("没有麦克风权限，无法录音。")
                    }
                }
            }
        @unknown default:
            statusText = L("没有麦克风权限，无法录音。")
        }
    }

    private func beginRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let name = "voice-\(UUID().uuidString).m4a"
            let url = FileStorage.url(for: name, subdir: "journeys")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let rec = try AVAudioRecorder(url: url, settings: settings)
            guard rec.record() else {
                FileStorage.deleteFile(fileName: name, subdir: "journeys")
                statusText = L("录音启动失败，请再试一次。")
                return
            }
            recorder = rec
            recordingFileName = name
            isRecording = true
            statusText = nil
        } catch {
            statusText = L("录音启动失败，请再试一次。")
        }
    }

    func stopRecording() {
        finishRecording(save: true)
    }

    private func finishRecording(save: Bool) {
        guard let rec = recorder else { return }
        rec.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let name = recordingFileName else { return }
        recordingFileName = nil
        if save {
            onSaved?(name)
        } else {
            // 半截录音（界面中途消失）直接丢弃，不留孤儿文件
            FileStorage.deleteFile(fileName: name, subdir: "journeys")
        }
    }

    // 播放

    func togglePlayback(fileName: String) {
        if isPlaying {
            stopPlayback()
            return
        }
        let url = FileStorage.url(for: fileName, subdir: "journeys")
        guard FileManager.default.fileExists(atPath: url.path) else {
            statusText = L("录音文件找不到了，可能已被删除。")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.play()
            player = p
            isPlaying = true
            statusText = nil
        } catch {
            statusText = String(format: L("播放失败：%@"), error.localizedDescription)
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    /// 界面消失时收尾：正在录的半截丢弃，播放停掉
    func stopAll() {
        if isRecording { finishRecording(save: false) }
        stopPlayback()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.player = nil
            self?.isPlaying = false
        }
    }
}

/// 旅程地图的共用画布：编辑器、海报、播放器三处共用同一张脸。
/// 背景按 backgroundRaw 取 AppTheme 三色之一，点缀只有右上角的太阳与底部两道山丘弧线；
/// 站点之间连一条虚线路径；站点有照片时是圆形照片点（可被照片 replace 编号点），否则是编号黄点。
/// 小人：头像照片（或默认笑脸）圆头 + 火柴人身体，脚踩在 characterPosition 给的点上；
/// 走路时的上下浮动由调用方通过 characterBob 传入，本视图只按给定的位置画。
struct JourneyMapView: View {
    let journey: JourneyData
    /// 小人脚下踩的点（相对坐标 0...1）；nil 时不画小人
    var characterPosition: CGPoint? = nil
    var characterVisible: Bool = false
    /// 点站点的回调：编辑器用来选中，播放器用来走过去 / 打开
    var onTapStop: ((JourneyStop) -> Void)? = nil
    /// 编辑器专用：站点可拖动改位，拖动时通过 onMoveStop 回报相对坐标
    var draggableStops: Bool = false
    var onMoveStop: ((UUID, Double, Double) -> Void)? = nil
    /// 编辑器里当前选中的站点（珊瑚红粗圈标记）
    var selectedStopID: UUID? = nil
    /// 小人的上下浮动偏移（走路时由播放器喂正弦值）
    var characterBob: CGFloat = 0

    private var bgColor: Color {
        switch journey.backgroundRaw {
        case "sunny": return AppTheme.sunny
        case "sky": return AppTheme.sky
        default: return AppTheme.paper
        }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                bgColor

                // 右上角的太阳
                Circle()
                    .fill(AppTheme.coral)
                    .overlay(Circle().stroke(AppTheme.ink, lineWidth: 2))
                    .frame(width: 44, height: 44)
                    .position(x: w * 0.85, y: h * 0.12)

                // 底部两道山丘弧线
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.92))
                    p.addQuadCurve(to: CGPoint(x: w * 0.62, y: h * 0.98),
                                   control: CGPoint(x: w * 0.3, y: h * 0.8))
                }
                .stroke(AppTheme.ink, lineWidth: 2)
                Path { p in
                    p.move(to: CGPoint(x: w * 0.42, y: h * 1.0))
                    p.addQuadCurve(to: CGPoint(x: w, y: h * 0.9),
                                   control: CGPoint(x: w * 0.72, y: h * 1.05))
                }
                .stroke(AppTheme.ink, lineWidth: 2)

                // 站点之间的虚线路径
                if journey.stops.count > 1 {
                    Path { p in
                        for (i, stop) in journey.stops.enumerated() {
                            let pt = CGPoint(x: stop.x * w, y: stop.y * h)
                            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                        }
                    }
                    .stroke(AppTheme.ink, style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                }

                ForEach(Array(journey.stops.enumerated()), id: \.element.id) { index, stop in
                    markerView(stop: stop, number: index + 1, size: geo.size)
                }

                if characterVisible, let pos = characterPosition {
                    characterView
                        .position(x: pos.x * w, y: pos.y * h - 43 + characterBob)
                }
            }
            .coordinateSpace(name: "journeyMap")
        }
    }

    /// 一个站点标记：手势（点选 / 拖动）先挂在标记本体上，最后才 .position 定位，
    /// 保证命中区跟着标记走而不是整块画布
    @ViewBuilder
    private func markerView(stop: JourneyStop, number: Int, size: CGSize) -> some View {
        let base = marker(stop: stop, number: number)
            .onTapGesture { onTapStop?(stop) }
        if draggableStops {
            base
                .gesture(
                    DragGesture(minimumDistance: 6, coordinateSpace: .named("journeyMap"))
                        .onChanged { value in
                            let nx = min(max(value.location.x / size.width, 0.05), 0.95)
                            let ny = min(max(value.location.y / size.height, 0.05), 0.95)
                            onMoveStop?(stop.id, Double(nx), Double(ny))
                        }
                )
                .position(x: stop.x * size.width, y: stop.y * size.height)
        } else {
            base
                .position(x: stop.x * size.width, y: stop.y * size.height)
        }
    }

    /// 标记本体：有照片 = 圆形照片点；没有 = 编号明黄点；选中时换珊瑚红粗圈
    private func marker(stop: JourneyStop, number: Int) -> some View {
        let selected = selectedStopID == stop.id
        return Group {
            if let file = stop.photoFile,
               let img = FileStorage.loadImage(fileName: file, subdir: "journeys") {
                Image(uiImage: img)
                    .resizable().scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())
            } else {
                ZStack {
                    Circle().fill(AppTheme.sunny)
                    Text("\(number)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                }
                .frame(width: 26, height: 26)
            }
        }
        .overlay(
            Circle().stroke(selected ? AppTheme.coral : AppTheme.ink,
                            lineWidth: selected ? 3 : 2)
        )
    }

    /// 小人：圆头（头像照片或默认笑脸）+ 火柴人身体，总高约 86，脚在底部
    private var characterView: some View {
        VStack(spacing: 0) {
            Group {
                if let file = journey.headFile,
                   let img = FileStorage.loadImage(fileName: file, subdir: "journeys") {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                } else {
                    ZStack {
                        Circle().fill(AppTheme.sunny)
                        Circle().fill(AppTheme.ink)
                            .frame(width: 4.5, height: 4.5)
                            .offset(x: -8, y: -3)
                        Circle().fill(AppTheme.ink)
                            .frame(width: 4.5, height: 4.5)
                            .offset(x: 8, y: -3)
                        Path { p in
                            p.addArc(center: CGPoint(x: 22, y: 23), radius: 8,
                                     startAngle: .degrees(30), endAngle: .degrees(150),
                                     clockwise: false)
                        }
                        .stroke(AppTheme.ink, lineWidth: 2)
                    }
                    .frame(width: 44, height: 44)
                }
            }
            .overlay(Circle().stroke(AppTheme.ink, lineWidth: 2.5))

            Path { p in
                p.move(to: CGPoint(x: 22, y: 2))
                p.addLine(to: CGPoint(x: 22, y: 20))
                p.move(to: CGPoint(x: 22, y: 8))
                p.addLine(to: CGPoint(x: 9, y: 16))
                p.move(to: CGPoint(x: 22, y: 8))
                p.addLine(to: CGPoint(x: 35, y: 16))
                p.move(to: CGPoint(x: 22, y: 20))
                p.addLine(to: CGPoint(x: 13, y: 40))
                p.move(to: CGPoint(x: 22, y: 20))
                p.addLine(to: CGPoint(x: 31, y: 40))
            }
            .stroke(AppTheme.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .frame(width: 44, height: 42)
        }
        .frame(width: 44, height: 86)
    }
}

/// 旅程地图编辑器：选背景与自己的头像，在地图上拖站点，给每个站点放照片 / 语音 / 文字，
/// 保存时把静态地图渲成封面海报存成一张卡（流程与动画信编辑器 saveLetter 对齐）
struct JourneyCardEditorView: View {
    @EnvironmentObject var contactStore: ContactStore
    @EnvironmentObject var cardStore: CardStore
    @Environment(\.dismiss) private var dismiss

    @State private var cardName = ""
    @State private var assignTo: UUID? = nil
    @State private var backgroundRaw = "paper"
    @State private var headFile: String? = nil
    @State private var stops: [JourneyStop] = JourneyCardEditorView.defaultStops()
    @State private var selectedStopID: UUID? = nil

    @State private var headItem: PhotosPickerItem? = nil
    @State private var stopPhotoItem: PhotosPickerItem? = nil
    /// 正在给哪个站点挑照片（打开选择器时把当时的选中站点记下来，读图回来照它写入）
    @State private var photoTargetID: UUID? = nil
    /// 正在给哪个站点录语音（录完的回调按它写入）
    @State private var voiceTargetID: UUID? = nil
    @State private var errorText: String? = nil

    @StateObject private var voiceBox = JourneyVoiceRecorder()

    /// 新站点的默认落点：从左下到右上的一条舒缓斜线，中间微微下凹，全站通用
    static func defaultPosition(index: Int, count: Int) -> (x: Double, y: Double) {
        let t = count <= 1 ? 0.5 : Double(index) / Double(count - 1)
        return (0.15 + 0.7 * t, 0.78 - 0.56 * t - 0.10 * sin(t * .pi))
    }

    static func defaultStops() -> [JourneyStop] {
        (0..<3).map { i in
            let p = defaultPosition(index: i, count: 3)
            return JourneyStop(x: p.x, y: p.y)
        }
    }

    private var previewData: JourneyData {
        JourneyData(stops: stops, headFile: headFile, backgroundRaw: backgroundRaw)
    }

    private var selectedIndex: Int? {
        guard let id = selectedStopID else { return nil }
        return stops.firstIndex(where: { $0.id == id })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    basicSection
                    mapSection
                    stopPanel
                }
                .padding()
            }
            .background(AppTheme.sunny)
            .navigationTitle(L("旅程地图"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("保存旅程")) { saveJourney() }
                }
            }
        }
        .onAppear {
            if selectedStopID == nil { selectedStopID = stops.first?.id }
            voiceBox.onSaved = { name in
                if let target = voiceTargetID,
                   let idx = stops.firstIndex(where: { $0.id == target }) {
                    stops[idx].voiceFile = name
                }
            }
        }
        .onDisappear { voiceBox.stopAll() }
        .onChange(of: headItem) { _, item in Task { await loadHeadImage(item) } }
        .onChange(of: stopPhotoItem) { _, item in
            photoTargetID = selectedStopID
            Task { await loadStopPhoto(item) }
        }
        .alert(L("提示"), isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button(L("好")) { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
    }

    private var basicSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L("卡片名称（可不填）"), text: $cardName)
                .textFieldStyle(.roundedBorder)
            Picker(L("送给（卡片池）"), selection: $assignTo) {
                Text(L("不指定")).tag(UUID?.none)
                ForEach(contactStore.contacts) { contact in
                    Text(contact.name).tag(UUID?.some(contact.id))
                }
            }
            Text(L("背景")).font(.subheadline).bold()
            Picker(L("背景"), selection: $backgroundRaw) {
                Text(L("纸白")).tag("paper")
                Text(L("明黄")).tag("sunny")
                Text(L("天蓝")).tag("sky")
            }
            .pickerStyle(.segmented)
            HStack(spacing: 12) {
                if let file = headFile,
                   let img = FileStorage.loadImage(fileName: file, subdir: "journeys") {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AppTheme.ink, lineWidth: 2))
                } else {
                    Circle()
                        .fill(AppTheme.sunny)
                        .frame(width: 40, height: 40)
                        .overlay(Circle().stroke(AppTheme.ink, lineWidth: 2))
                        .overlay(Image(systemName: "person.fill").foregroundStyle(AppTheme.ink))
                }
                PhotosPicker(selection: $headItem, matching: .images) {
                    Label(L("选我的头像"), systemImage: "person.crop.circle")
                }
                if headFile != nil {
                    Button(L("删除"), role: .destructive) { headFile = nil }
                }
            }
        }
    }

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            JourneyMapView(
                journey: previewData,
                characterPosition: stops.first.map { CGPoint(x: $0.x, y: $0.y) },
                characterVisible: !stops.isEmpty,
                onTapStop: { stop in selectedStopID = stop.id },
                draggableStops: true,
                onMoveStop: { id, nx, ny in
                    if let idx = stops.firstIndex(where: { $0.id == id }) {
                        stops[idx].x = nx
                        stops[idx].y = ny
                    }
                },
                selectedStopID: selectedStopID
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.ink, lineWidth: 2))

            Stepper(value: stopCountBinding, in: 2...8) {
                Text(String(format: L("站点数：%d"), stops.count))
            }
        }
    }

    private var stopCountBinding: Binding<Int> {
        Binding(
            get: { stops.count },
            set: { newCount in setStopCount(newCount) }
        )
    }

    /// 站数增减：加站时按默认落点公式接在后面；减站从末尾去掉，选中被去掉的站就改选最后一站
    private func setStopCount(_ newCount: Int) {
        if newCount > stops.count {
            for i in stops.count..<newCount {
                let p = Self.defaultPosition(index: i, count: newCount)
                stops.append(JourneyStop(x: p.x, y: p.y))
            }
        } else if newCount < stops.count {
            stops.removeLast(stops.count - newCount)
            if let sel = selectedStopID, !stops.contains(where: { $0.id == sel }) {
                selectedStopID = stops.last?.id
            }
        }
    }

    @ViewBuilder
    private var stopPanel: some View {
        if let idx = selectedIndex {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(format: L("第 %d / %d 站"), idx + 1, stops.count))
                    .font(.subheadline).bold()

                HStack(spacing: 12) {
                    if let file = stops[idx].photoFile,
                       let img = FileStorage.loadImage(fileName: file, subdir: "journeys") {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(width: 54, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    PhotosPicker(selection: $stopPhotoItem, matching: .images) {
                        Label(stops[idx].photoFile == nil ? L("加照片") : L("换照片"),
                              systemImage: "photo")
                    }
                }

                voiceRow(for: idx)

                TextField(L("这一站想说的话"), text: textBinding(for: idx))
                    .textFieldStyle(.roundedBorder)

                if stops.count > 2 {
                    Button(L("删除这一站"), role: .destructive) {
                        deleteSelectedStop()
                    }
                }

                if let status = voiceBox.statusText {
                    Text(status).font(.caption).foregroundStyle(.orange)
                }
            }
        } else {
            Text(L("点一个站点，给它放照片、语音和文字。"))
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    /// 某一站的语音行：没录 = 录语音；录音中 = 停止录音；已录 = 播放 / 停止 + 删除
    @ViewBuilder
    private func voiceRow(for idx: Int) -> some View {
        HStack(spacing: 12) {
            if voiceBox.isRecording && voiceTargetID == stops[idx].id {
                Button(role: .destructive) {
                    voiceBox.stopRecording()
                } label: {
                    Label(L("停止录音"), systemImage: "stop.circle.fill")
                }
                Text(L("正在录音……")).font(.caption).foregroundStyle(.secondary)
            } else if let voice = stops[idx].voiceFile {
                Button {
                    voiceBox.togglePlayback(fileName: voice)
                } label: {
                    Label(voiceBox.isPlaying ? L("停止播放") : L("播放录音"),
                          systemImage: voiceBox.isPlaying ? "stop.circle" : "play.circle")
                }
                Button(role: .destructive) {
                    voiceBox.stopPlayback()
                    FileStorage.deleteFile(fileName: voice, subdir: "journeys")
                    stops[idx].voiceFile = nil
                } label: {
                    Label(L("删除录音"), systemImage: "trash")
                }
            } else {
                Button {
                    voiceTargetID = stops[idx].id
                    voiceBox.startRecording()
                } label: {
                    Label(L("录语音"), systemImage: "mic.circle")
                }
            }
        }
    }

    /// 站点文字是可选值：输入框里清空 = 存 nil
    private func textBinding(for idx: Int) -> Binding<String> {
        Binding(
            get: { stops[idx].text ?? "" },
            set: { stops[idx].text = $0.isEmpty ? nil : $0 }
        )
    }

    private func deleteSelectedStop() {
        guard let idx = selectedIndex, stops.count > 2 else { return }
        stops.remove(at: idx)
        selectedStopID = stops[min(idx, stops.count - 1)].id
    }

    private func loadHeadImage(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }
        defer { headItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            if let file = JourneyMediaHelper.saveImage(data: data, prefix: "head-", maxSide: 600) {
                headFile = file
            }
        } catch {
            errorText = String(format: L("读取照片失败：%@"), error.localizedDescription)
        }
    }

    private func loadStopPhoto(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }
        defer { stopPhotoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let target = photoTargetID ?? selectedStopID
            if let file = JourneyMediaHelper.saveImage(data: data, prefix: "stop-", maxSide: 1200),
               let target = target,
               let idx = stops.firstIndex(where: { $0.id == target }) {
                stops[idx].photoFile = file
            }
        } catch {
            errorText = String(format: L("读取照片失败：%@"), error.localizedDescription)
        }
    }

    /// 保存流程与动画信 saveLetter 对齐：先渲封面海报落盘，再建卡入池，建卡失败回滚删图
    private func saveJourney() {
        let data = previewData
        let poster = JourneyMapView(
            journey: data,
            characterPosition: stops.first.map { CGPoint(x: $0.x, y: $0.y) },
            characterVisible: !stops.isEmpty,
            onTapStop: nil
        )
        .frame(width: 330, height: 440)
        let renderer = ImageRenderer(content: poster)
        renderer.scale = 3
        guard let uiImage = renderer.uiImage, let png = uiImage.pngData() else {
            errorText = L("保存失败，请再试一次。")
            return
        }
        let fileName = "card-\(UUID().uuidString).png"
        let url = FileStorage.url(for: fileName, subdir: "cards")
        do {
            try png.write(to: url)
        } catch {
            errorText = String(format: L("保存失败：%@"), error.localizedDescription)
            return
        }
        let name = cardName.trimmingCharacters(in: .whitespaces).isEmpty ? L("我的旅程") : cardName
        let target = assignTo.flatMap { contactStore.contact(id: $0) }
        let card = CardDesign(name: name, imageFile: fileName,
                              assignedContactID: target?.id, journey: data)
        guard cardStore.add(card) else {
            try? FileManager.default.removeItem(at: url)
            errorText = L("保存失败（存储空间可能不足），请再试一次。")
            return
        }
        if var contact = target {
            if !contact.cardPoolIDs.contains(card.id) {
                contact.cardPoolIDs.append(card.id)
                contactStore.update(contact)
            }
        }
        dismiss()
    }
}

/// 旅程播放器：小人从第一站出发，点「下一站」或点任意站点就走过去（约 1.1 秒，边走边轻轻上下浮），
/// 到站后由用户点「打开这一站」或再点一次当前站点，翻开这一站的照片 / 语音 / 文字
struct JourneyPlayerView: View {
    let journey: JourneyData
    @Environment(\.dismiss) private var dismiss

    @State private var currentIndex = 0
    @State private var charPos = CGPoint(x: 0.5, y: 0.5)
    @State private var bob: CGFloat = 0
    @State private var isWalking = false
    @State private var contentStop: JourneyStop? = nil
    @State private var walkTask: Task<Void, Never>? = nil

    private var currentStop: JourneyStop? {
        journey.stops.indices.contains(currentIndex) ? journey.stops[currentIndex] : nil
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Spacer()
                Button(L("关闭")) { dismiss() }
            }

            JourneyMapView(
                journey: journey,
                characterPosition: charPos,
                characterVisible: !journey.stops.isEmpty,
                onTapStop: { stop in tapStop(stop) },
                characterBob: bob
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.ink, lineWidth: 2))

            Text(String(format: L("第 %d / %d 站"), currentIndex + 1, max(journey.stops.count, 1)))
                .font(.subheadline).foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(L("上一站")) { goTo(currentIndex - 1) }
                    .buttonStyle(InkButtonStyle())
                    .disabled(isWalking || currentIndex <= 0)
                Button(L("打开这一站")) {
                    if let stop = currentStop { contentStop = stop }
                }
                .buttonStyle(SunnyButtonStyle())
                .disabled(isWalking || journey.stops.isEmpty)
                Button(L("下一站")) { goTo(currentIndex + 1) }
                    .buttonStyle(InkButtonStyle())
                    .disabled(isWalking || currentIndex >= journey.stops.count - 1)
            }
        }
        .padding()
        .onAppear {
            if let first = journey.stops.first {
                charPos = CGPoint(x: first.x, y: first.y)
            }
        }
        .onDisappear { walkTask?.cancel() }
        .sheet(item: $contentStop) { stop in
            JourneyStopView(stop: stop)
        }
    }

    /// 点站点：点别的站 = 走过去；点脚下这一站 = 打开它
    private func tapStop(_ stop: JourneyStop) {
        guard !isWalking,
              let idx = journey.stops.firstIndex(where: { $0.id == stop.id }) else { return }
        if idx == currentIndex {
            contentStop = stop
        } else {
            goTo(idx)
        }
    }

    /// 走路动画：14 步插值走完，每步约 80 毫秒，途中用正弦给一点上下浮动；走完才更新当前站
    private func goTo(_ target: Int) {
        guard journey.stops.indices.contains(target),
              target != currentIndex, !isWalking else { return }
        let from = charPos
        let dest = journey.stops[target]
        let to = CGPoint(x: dest.x, y: dest.y)
        isWalking = true
        walkTask = Task { @MainActor in
            let steps = 14
            for i in 1...steps {
                if Task.isCancelled { return }
                let t = Double(i) / Double(steps)
                charPos = CGPoint(x: from.x + (to.x - from.x) * CGFloat(t),
                                  y: from.y + (to.y - from.y) * CGFloat(t))
                bob = CGFloat(sin(t * .pi * 4)) * 4
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
            charPos = to
            bob = 0
            currentIndex = target
            isWalking = false
        }
    }
}

/// 站点内容页（翻翻书的这一页）：照片大图 + 文字 + 语音播放，三样都没有就给一句空提示
struct JourneyStopView: View {
    let stop: JourneyStop
    @Environment(\.dismiss) private var dismiss
    @StateObject private var voiceBox = JourneyVoiceRecorder()

    private var photo: UIImage? {
        guard let file = stop.photoFile else { return nil }
        return FileStorage.loadImage(fileName: file, subdir: "journeys")
    }

    private var hasContent: Bool {
        photo != nil
            || !(stop.text?.isEmpty ?? true)
            || stop.voiceFile != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let img = photo {
                        Image(uiImage: img)
                            .resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if let text = stop.text, !text.isEmpty {
                        Text(text)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let voice = stop.voiceFile {
                        Button {
                            voiceBox.togglePlayback(fileName: voice)
                        } label: {
                            Label(voiceBox.isPlaying ? L("停止播放") : L("播放录音"),
                                  systemImage: voiceBox.isPlaying ? "stop.circle" : "play.circle")
                        }
                        .buttonStyle(InkButtonStyle())
                    }
                    if !hasContent {
                        Text(L("这一站还没有放东西。"))
                            .foregroundStyle(.secondary)
                    }
                    if let status = voiceBox.statusText {
                        Text(status).font(.caption).foregroundStyle(.orange)
                    }
                }
                .padding()
            }
            .navigationTitle(L("旅程地图"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("关闭")) { dismiss() }
                }
            }
        }
        .onDisappear { voiceBox.stopAll() }
    }
}

struct LetterCardEditorView: View {
    @EnvironmentObject var contactStore: ContactStore
    @EnvironmentObject var cardStore: CardStore
    @Environment(\.dismiss) private var dismiss

    @State private var cardName = ""
    @State private var assignTo: UUID? = nil
    @State private var titleText = "HAPPY BIRTHDAY"
    @State private var letterText = ""
    @State private var walkerKind: String? = nil
    @State private var walkerValue: String? = nil
    @State private var topMediaFile: String? = nil
    @State private var topMediaIsVideo = false
    @State private var bottomMediaFile: String? = nil
    @State private var bottomMediaIsVideo = false
    @State private var fixedStickers: [LetterFixedSticker] = []

    @State private var topImageItem: PhotosPickerItem? = nil
    @State private var topVideoItem: PhotosPickerItem? = nil
    @State private var bottomImageItem: PhotosPickerItem? = nil
    @State private var bottomVideoItem: PhotosPickerItem? = nil
    @State private var memoryImageItem: PhotosPickerItem? = nil
    @State private var memoryTargetID: UUID? = nil
    @State private var stickerSheetMode: StickerSheetMode? = nil
    @State private var libraryStickers: [String] = []
    @State private var errorText: String? = nil

    private enum StickerSheetMode: Int, Identifiable {
        case walker, addFixed
        var id: Int { rawValue }
    }

    private let emojiPalette = ["🌸", "🌺", "🌻", "🌹", "🍀", "🍃", "⭐️", "💛",
                                "❤️", "🎂", "🎈", "🎁", "🦋", "🌙", "☀️", "🌈",
                                "🍓", "🍒", "🐰", "🐱", "✨", "🎀", "🕊️", "🍰"]

    private var titleCount: Int { max(titleText.count, 1) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    basicSection
                    walkerSection
                    mediaSection(title: L("上方画面"), file: topMediaFile, isVideo: topMediaIsVideo,
                                 imageItem: $topImageItem, videoItem: $topVideoItem,
                                 onClear: { topMediaFile = nil; topMediaIsVideo = false })
                    mediaSection(title: L("下方画面"), file: bottomMediaFile, isVideo: bottomMediaIsVideo,
                                 imageItem: $bottomImageItem, videoItem: $bottomVideoItem,
                                 onClear: { bottomMediaFile = nil; bottomMediaIsVideo = false })
                    fixedSection
                }
                .padding()
            }
            .background(AppTheme.sunny)
            .navigationTitle(L("动画信"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("保存动画信")) { saveLetter() }
                }
            }
        }
        .onChange(of: topImageItem) { _, item in Task { await loadMediaImage(item, isTop: true) } }
        .onChange(of: bottomImageItem) { _, item in Task { await loadMediaImage(item, isTop: false) } }
        .onChange(of: topVideoItem) { _, item in Task { await loadMediaVideo(item, isTop: true) } }
        .onChange(of: bottomVideoItem) { _, item in Task { await loadMediaVideo(item, isTop: false) } }
        .onChange(of: memoryImageItem) { _, item in Task { await loadMemoryImage(item) } }
        .sheet(item: $stickerSheetMode) { mode in
            stickerLibrarySheet(mode: mode)
        }
        .alert(L("提示"), isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button(L("好")) { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
    }

    private var basicSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L("卡片名称（可不填）"), text: $cardName)
                .textFieldStyle(.roundedBorder)
            Picker(L("送给（卡片池）"), selection: $assignTo) {
                Text(L("不指定")).tag(UUID?.none)
                ForEach(contactStore.contacts) { contact in
                    Text(contact.name).tag(UUID?.some(contact.id))
                }
            }
            Text(L("开场白")).font(.subheadline).bold()
            TextField("HAPPY BIRTHDAY", text: $titleText)
                .textFieldStyle(.roundedBorder)
            Text(L("信的内容")).font(.subheadline).bold()
            TextEditor(text: $letterText)
                .frame(height: 110)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.3)))
        }
    }

    private var walkerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("走路贴纸")).font(.subheadline).bold()
            HStack(spacing: 12) {
                Group {
                    if walkerKind == "photo", let v = walkerValue,
                       let img = FileStorage.loadImage(fileName: v, subdir: "stickers") {
                        Image(uiImage: img).resizable().scaledToFit()
                    } else if walkerKind == "emoji", let v = walkerValue {
                        Text(v).font(.system(size: 44))
                    } else {
                        Image(systemName: "figure.walk")
                            .font(.largeTitle).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 64, height: 64)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                Button {
                    libraryStickers = FileStorage.stickerFileNames()
                    stickerSheetMode = .walker
                } label: {
                    Label(L("选贴纸"), systemImage: "scissors")
                }
                if walkerKind != nil {
                    Button(L("清除")) { walkerKind = nil; walkerValue = nil }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(emojiPalette, id: \.self) { symbol in
                        Button {
                            walkerKind = "emoji"
                            walkerValue = symbol
                        } label: {
                            Text(symbol).font(.title3)
                                .frame(width: 36, height: 36)
                                .background(Color.secondary.opacity(0.10))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func mediaSection(title: String, file: String?, isVideo: Bool,
                              imageItem: Binding<PhotosPickerItem?>,
                              videoItem: Binding<PhotosPickerItem?>,
                              onClear: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).bold()
            if let file = file {
                if isVideo {
                    Label(L("已选一段视频"), systemImage: "film")
                        .font(.subheadline)
                } else if let img = FileStorage.loadImage(fileName: file, subdir: "letters") {
                    Image(uiImage: img).resizable().scaledToFit()
                        .frame(height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            HStack(spacing: 12) {
                PhotosPicker(selection: imageItem, matching: .images) {
                    Label(L("选图片"), systemImage: "photo")
                }
                PhotosPicker(selection: videoItem, matching: .videos) {
                    Label(L("选视频"), systemImage: "video")
                }
                if file != nil {
                    Button(L("清除"), role: .destructive) { onClear() }
                }
            }
        }
    }

    private var fixedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("固定贴纸")).font(.subheadline).bold()
            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.06))
                    Text(titleText.isEmpty ? "HAPPY BIRTHDAY" : titleText)
                        .font(.headline)
                        .frame(width: geo.size.width, alignment: .center)
                        .padding(.top, 10)
                        .frame(maxHeight: .infinity, alignment: .top)
                    ForEach($fixedStickers) { $sticker in
                        LetterFixedHandle(sticker: $sticker, stageSize: geo.size)
                    }
                }
                .coordinateSpace(.named("letterStageEdit"))
            }
            .frame(height: 300)
            HStack(spacing: 12) {
                Button {
                    libraryStickers = FileStorage.stickerFileNames()
                    stickerSheetMode = .addFixed
                } label: {
                    Label(L("添加图片贴纸"), systemImage: "scissors")
                }
                Menu {
                    ForEach(emojiPalette, id: \.self) { symbol in
                        Button(symbol) { addFixedSticker(kind: "emoji", value: symbol) }
                    }
                } label: {
                    Label(L("添加emoji贴纸"), systemImage: "face.smiling")
                }
                Button {
                    addFixedDot()
                } label: {
                    Label(L("圆点"), systemImage: "circle.fill")
                }
            }
            ForEach($fixedStickers) { $sticker in
                fixedStickerRow(sticker: $sticker)
            }
        }
    }

    private func fixedStickerRow(sticker: Binding<LetterFixedSticker>) -> some View {
        let s = sticker.wrappedValue
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Group {
                    if s.isDot {
                        LetterDotView(size: 30)
                    } else if s.kind == "photo",
                       let img = FileStorage.loadImage(fileName: s.value, subdir: "stickers") {
                        Image(uiImage: img).resizable().scaledToFit()
                    } else {
                        Text(s.value).font(.system(size: 30))
                    }
                }
                .frame(width: 44, height: 44)
                Stepper(String(format: L("第 %d 个字时出现"), s.appearAtStep),
                        value: sticker.appearAtStep, in: 0...titleCount)
                Button(role: .destructive) {
                    fixedStickers.removeAll { $0.id == s.id }
                } label: {
                    Image(systemName: "trash")
                }
            }
            TextField(L("回忆文字（点开时显示）"), text: Binding(
                get: { s.memoryText ?? "" },
                set: { sticker.wrappedValue.memoryText = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
            HStack(spacing: 10) {
                if let f = s.memoryImageFile,
                   let img = FileStorage.loadImage(fileName: f, subdir: "letters") {
                    Image(uiImage: img).resizable().scaledToFit()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                PhotosPicker(selection: $memoryImageItem, matching: .images) {
                    Label(L("回忆照片"), systemImage: "photo.badge.plus")
                }
                .simultaneousGesture(TapGesture().onEnded { memoryTargetID = s.id })
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func stickerLibrarySheet(mode: StickerSheetMode) -> some View {
        NavigationStack {
            Group {
                if libraryStickers.isEmpty {
                    ContentUnavailableView(L("还没有贴纸"),
                                           systemImage: "square.grid.2x2",
                                           description: Text(L("先用「照片做贴纸」抠一张，做好后会出现在这里，以后做新卡可以直接选。")))
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                            ForEach(libraryStickers, id: \.self) { fileName in
                                Button {
                                    if mode == .walker {
                                        walkerKind = "photo"
                                        walkerValue = fileName
                                    } else {
                                        addFixedSticker(kind: "photo", value: fileName)
                                    }
                                    stickerSheetMode = nil
                                } label: {
                                    if let img = FileStorage.loadImage(fileName: fileName, subdir: "stickers") {
                                        Image(uiImage: img)
                                            .resizable().scaledToFit()
                                            .frame(width: 96, height: 96)
                                            .background(Color.secondary.opacity(0.08))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    } else {
                                        Image(systemName: "photo")
                                            .frame(width: 96, height: 96)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(L("选贴纸"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("关闭")) { stickerSheetMode = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func addFixedSticker(kind: String, value: String) {
        let sticker = LetterFixedSticker(kind: kind, value: value,
                                         appearAtStep: titleCount / 2,
                                         x: 0.5, y: 0.62)
        fixedStickers.append(sticker)
    }

    /// 加圆点：不需要贴纸图或 emoji，kind/value 按约定置空，
    /// 要藏的话就写在下面那行「回忆文字」里（播放时点圆点打开回忆页看）
    private func addFixedDot() {
        let dot = LetterFixedSticker(kind: "dot", value: "",
                                     appearAtStep: titleCount / 2,
                                     x: 0.5, y: 0.62, isDot: true)
        fixedStickers.append(dot)
    }

    private func loadMediaImage(_ item: PhotosPickerItem?, isTop: Bool) async {
        guard let item = item else { return }
        defer {
            if isTop { topImageItem = nil } else { bottomImageItem = nil }
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let file = LetterMediaHelper.saveImage(image) else {
                errorText = L("没有读到这张照片，请换一张试试。")
                return
            }
            if isTop { topMediaFile = file; topMediaIsVideo = false }
            else { bottomMediaFile = file; bottomMediaIsVideo = false }
        } catch {
            errorText = String(format: L("读取照片失败：%@"), error.localizedDescription)
        }
    }

    private func loadMediaVideo(_ item: PhotosPickerItem?, isTop: Bool) async {
        guard let item = item else { return }
        defer {
            if isTop { topVideoItem = nil } else { bottomVideoItem = nil }
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let file = LetterMediaHelper.saveVideoData(data) else {
                errorText = L("没有读到这段视频，请换一段试试。")
                return
            }
            if isTop { topMediaFile = file; topMediaIsVideo = true }
            else { bottomMediaFile = file; bottomMediaIsVideo = true }
        } catch {
            errorText = String(format: L("读取照片失败：%@"), error.localizedDescription)
        }
    }

    private func loadMemoryImage(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }
        defer { memoryImageItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let file = LetterMediaHelper.saveImage(image),
                  let target = memoryTargetID,
                  let idx = fixedStickers.firstIndex(where: { $0.id == target }) else {
                return
            }
            fixedStickers[idx].memoryImageFile = file
        } catch {
            errorText = String(format: L("读取照片失败：%@"), error.localizedDescription)
        }
    }

    private func saveLetter() {
        let title = titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "HAPPY BIRTHDAY" : titleText
        let data = LetterTemplateData(titleText: title, letterText: letterText,
                                      topMediaFile: topMediaFile, topMediaIsVideo: topMediaIsVideo,
                                      bottomMediaFile: bottomMediaFile, bottomMediaIsVideo: bottomMediaIsVideo,
                                      walkerKind: walkerKind, walkerValue: walkerValue,
                                      fixedStickers: fixedStickers)
        let renderer = ImageRenderer(content: LetterPosterView(data: data))
        renderer.scale = 2
        guard let uiImage = renderer.uiImage, let png = uiImage.pngData() else {
            errorText = L("保存失败，请再试一次。")
            return
        }
        let fileName = "card-\(UUID().uuidString).png"
        let url = FileStorage.url(for: fileName, subdir: "cards")
        do {
            try png.write(to: url)
        } catch {
            errorText = String(format: L("保存失败：%@"), error.localizedDescription)
            return
        }
        let name = cardName.trimmingCharacters(in: .whitespaces).isEmpty ? title : cardName
        let target = assignTo.flatMap { contactStore.contact(id: $0) }
        let card = CardDesign(name: name, imageFile: fileName,
                              assignedContactID: target?.id, letter: data)
        guard cardStore.add(card) else {
            try? FileManager.default.removeItem(at: url)
            errorText = L("保存失败（存储空间可能不足），请再试一次。")
            return
        }
        if var contact = target {
            if !contact.cardPoolIDs.contains(card.id) {
                contact.cardPoolIDs.append(card.id)
                contactStore.update(contact)
            }
        }
        dismiss()
    }
}

/// 系统分享表（发视频文件 / 网页文件给对方）
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// 导出用的图片素材（视频画面取第一帧当静态图）
struct LetterExportAssets {
    var topImage: UIImage? = nil
    var bottomImage: UIImage? = nil
    var walkerImage: UIImage? = nil
    var fixedImages: [UUID: UIImage] = [:]
}

enum LetterExportLoader {
    static func loadAssets(data: LetterTemplateData) -> LetterExportAssets {
        var a = LetterExportAssets()
        a.topImage = mediaImage(file: data.topMediaFile, isVideo: data.topMediaIsVideo)
        a.bottomImage = mediaImage(file: data.bottomMediaFile, isVideo: data.bottomMediaIsVideo)
        if data.walkerKind == "photo", let v = data.walkerValue {
            a.walkerImage = FileStorage.loadImage(fileName: v, subdir: "stickers")
        }
        for s in data.fixedStickers where s.kind == "photo" {
            a.fixedImages[s.id] = FileStorage.loadImage(fileName: s.value, subdir: "stickers")
        }
        return a
    }

    static func mediaImage(file: String?, isVideo: Bool) -> UIImage? {
        guard let file = file else { return nil }
        if !isVideo {
            return FileStorage.loadImage(fileName: file, subdir: "letters")
        }
        let url = FileStorage.url(for: file, subdir: "letters")
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        if let cg = try? generator.copyCGImage(at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil) {
            return UIImage(cgImage: cg)
        }
        return nil
    }
}

/// 导出视频的帧画面（360×540 点，渲染 scale 2 → 720×1080）
struct LetterExportStageView: View {
    let data: LetterTemplateData
    let step: Int
    let assets: LetterExportAssets

    private var titleChars: [Character] { Array(data.titleText) }

    var body: some View {
        ZStack {
            PaperView(kind: .cream)
            VStack(spacing: 8) {
                if let img = assets.topImage {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(height: 92).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                stage.frame(height: 180)
                Text(data.letterText)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .opacity(step >= titleChars.count ? 1 : 0)
                if let img = assets.bottomImage {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(height: 92).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(14)
        }
        .frame(width: 360, height: 540)
    }

    private var stage: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Text(String(titleChars.prefix(step)))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .frame(width: geo.size.width, alignment: .center)
                    .padding(.top, 4)
                walkerView
                    .position(x: walkerX(in: geo.size.width), y: 78)
                ForEach(data.fixedStickers) { sticker in
                    if step >= sticker.appearAtStep {
                        fixedView(sticker)
                            .position(x: sticker.x * geo.size.width,
                                      y: sticker.y * geo.size.height)
                    }
                }
            }
        }
    }

    private func walkerX(in width: CGFloat) -> CGFloat {
        guard !titleChars.isEmpty else { return width / 2 }
        let progress = Double(step) / Double(titleChars.count)
        return 30 + (width - 60) * progress
    }

    @ViewBuilder
    private var walkerView: some View {
        if let img = assets.walkerImage {
            Image(uiImage: img).resizable().scaledToFit().frame(width: 50, height: 50)
        } else if data.walkerKind == "emoji", let v = data.walkerValue {
            Text(v).font(.system(size: 38))
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func fixedView(_ sticker: LetterFixedSticker) -> some View {
        if sticker.kind == "photo", let img = assets.fixedImages[sticker.id] {
            Image(uiImage: img).resizable().scaledToFit().frame(width: 46, height: 46)
        } else if sticker.kind == "emoji" {
            Text(sticker.value).font(.system(size: 34))
        } else {
            EmptyView()
        }
    }
}

/// 把动画信逐帧渲染成 MP4：对方任何手机点开就能播（视频里贴纸不可点）
enum LetterVideoExporter {
    @MainActor
    static func exportMP4(data: LetterTemplateData) async -> URL? {
        let assets = LetterExportLoader.loadAssets(data: data)
        let width = 720
        let height = 1080
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("letter-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                                                             sourcePixelBufferAttributes: attributes)
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let totalSteps = max(Array(data.titleText).count, 1)
        let frameCount = totalSteps + 1 + 4   // step 0...totalSteps + 结尾定格约 2 秒
        for frame in 0..<frameCount {
            let step = min(frame, totalSteps)
            let view = LetterExportStageView(data: data, step: step, assets: assets)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let uiImage = renderer.uiImage, let cgImage = uiImage.cgImage,
                  let pool = adaptor.pixelBufferPool,
                  let buffer = pixelBuffer(from: cgImage, pool: pool) else {
                writer.cancelWriting()
                return nil
            }
            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            let time = CMTime(value: CMTimeValue(frame) * 30, timescale: 60)
            if !adaptor.append(buffer, withPresentationTime: time) {
                writer.cancelWriting()
                return nil
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        return writer.status == .completed ? url : nil
    }

    private static func pixelBuffer(from cgImage: CGImage, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var out: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out) == kCVReturnSuccess,
              let buffer = out else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                      width: w, height: h,
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(h))
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        return buffer
    }
}

/// 把动画信打包成单个 HTML 文件：对方用浏览器打开就能播，固定贴纸可点开回忆
enum LetterHTMLExporter {
    static func exportHTML(data: LetterTemplateData) -> URL? {
        var stickerDivs = ""
        var overlayDivs = ""
        for (i, s) in data.fixedStickers.enumerated() {
            let content: String
            if s.kind == "photo",
               let img = FileStorage.loadImage(fileName: s.value, subdir: "stickers"),
               let uri = jpegDataURI(img) {
                content = "<img src=\"\(uri)\">"
            } else {
                content = htmlEscape(s.value)
            }
            let hasMemory = (s.memoryText?.isEmpty == false) || s.memoryImageFile != nil
            let onclick = hasMemory ? " onclick=\"openMemory(\(i))\"" : ""
            stickerDivs += "<div class=\"fixed\" data-step=\"\(s.appearAtStep)\" style=\"left:\(percent(s.x));top:\(percent(s.y))\"\(onclick)>\(content)</div>\n"
            var inner = "<button class=\"close\" onclick=\"closeMemory(\(i))\">✕</button>"
            if let f = s.memoryImageFile,
               let img = FileStorage.loadImage(fileName: f, subdir: "letters"),
               let uri = jpegDataURI(img) {
                inner += "<img src=\"\(uri)\">"
            }
            if let t = s.memoryText, !t.isEmpty {
                inner += "<p>\(htmlEscape(t))</p>"
            }
            overlayDivs += "<div class=\"overlay\" id=\"mem\(i)\"><div class=\"sheet\">\(inner)</div></div>\n"
        }

        let walkerHTML: String
        if data.walkerKind == "photo", let v = data.walkerValue,
           let img = FileStorage.loadImage(fileName: v, subdir: "stickers"),
           let uri = jpegDataURI(img) {
            walkerHTML = "<img src=\"\(uri)\">"
        } else if data.walkerKind == "emoji", let v = data.walkerValue {
            walkerHTML = htmlEscape(v)
        } else {
            walkerHTML = ""
        }

        let html = """
        <!DOCTYPE html>
        <html lang="zh">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>💌</title>
        <style>
        body{margin:0;background:#f3ead9;font-family:-apple-system,'PingFang SC',sans-serif;}
        .card{max-width:430px;margin:0 auto;background:#fff8ea;min-height:100vh;padding:18px 16px 30px;box-sizing:border-box;}
        .media{width:100%;border-radius:12px;display:block;margin-top:10px;}
        .stage{position:relative;height:300px;margin-top:10px;}
        .title{font-size:30px;font-weight:800;text-align:center;min-height:44px;padding-top:4px;}
        .walker{position:absolute;top:66px;width:56px;transform:translateX(-50%);font-size:44px;text-align:center;}
        .walker img{width:56px;height:56px;object-fit:contain;}
        .fixed{position:absolute;width:54px;transform:translate(-50%,-50%);display:none;font-size:40px;text-align:center;cursor:pointer;}
        .fixed img{width:54px;height:54px;object-fit:contain;}
        .letter{white-space:pre-wrap;line-height:1.8;font-size:16px;opacity:0;transition:opacity .8s;background:#fff;border-radius:12px;padding:14px;margin-top:6px;}
        .replay{display:block;margin:16px auto 0;font-size:15px;padding:8px 18px;border-radius:999px;border:1px solid #c9a86a;background:#fff;color:#8a6d2f;}
        .overlay{position:fixed;inset:0;background:rgba(0,0,0,.45);display:none;align-items:center;justify-content:center;z-index:9;}
        .sheet{background:#fff;border-radius:14px;padding:18px;max-width:86vw;max-height:84vh;overflow:auto;position:relative;}
        .sheet img{width:100%;border-radius:10px;}
        .sheet p{line-height:1.7;}
        .close{position:absolute;right:8px;top:6px;border:none;background:none;font-size:18px;cursor:pointer;}
        </style>
        </head>
        <body>
        <div class="card">
        \(mediaHTML(file: data.topMediaFile, isVideo: data.topMediaIsVideo))
        <div class="stage">
        <div class="title" id="title"></div>
        <div class="walker" id="walker">\(walkerHTML)</div>
        \(stickerDivs)</div>
        <div class="letter" id="letter"></div>
        \(mediaHTML(file: data.bottomMediaFile, isVideo: data.bottomMediaIsVideo))
        <button class="replay" onclick="restart()">↻ Replay</button>
        </div>
        \(overlayDivs)
        <script>
        const TITLE = \(jsString(data.titleText));
        const LETTER = \(jsString(data.letterText));
        const TOTAL = TITLE.length;
        let step = 0, timer = null;
        const titleEl = document.getElementById('title');
        const walkerEl = document.getElementById('walker');
        const letterEl = document.getElementById('letter');
        letterEl.textContent = LETTER;
        function render(){
          titleEl.textContent = TITLE.slice(0, step);
          const p = TOTAL > 0 ? step / TOTAL : 0;
          walkerEl.style.left = (9 + 82 * p) + '%';
          document.querySelectorAll('.fixed').forEach(el => {
            el.style.display = step >= parseInt(el.dataset.step) ? 'block' : 'none';
          });
          letterEl.style.opacity = step >= TOTAL ? '1' : '0';
        }
        function play(){
          clearInterval(timer);
          step = 0; render();
          timer = setInterval(() => {
            step++;
            render();
            if (step >= TOTAL) clearInterval(timer);
          }, 500);
        }
        function restart(){ play(); }
        function openMemory(i){ document.getElementById('mem' + i).style.display = 'flex'; }
        function closeMemory(i){ document.getElementById('mem' + i).style.display = 'none'; }
        play();
        </script>
        </body>
        </html>
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("letter-\(UUID().uuidString).html")
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch { return nil }
    }

    private static func mediaHTML(file: String?, isVideo: Bool) -> String {
        guard let file = file else { return "" }
        if isVideo {
            let url = FileStorage.url(for: file, subdir: "letters")
            guard let d = try? Data(contentsOf: url) else { return "" }
            return "<video class=\"media\" src=\"data:video/mp4;base64,\(d.base64EncodedString())\" autoplay muted loop playsinline controls></video>"
        }
        guard let img = FileStorage.loadImage(fileName: file, subdir: "letters"),
              let uri = jpegDataURI(img) else { return "" }
        return "<img class=\"media\" src=\"\(uri)\">"
    }

    private static func jpegDataURI(_ img: UIImage) -> String? {
        guard let d = img.jpegData(compressionQuality: 0.8) else { return nil }
        return "data:image/jpeg;base64,\(d.base64EncodedString())"
    }

    private static func htmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func percent(_ v: Double) -> String {
        String(format: "%.1f%%", v * 100)
    }

    /// 把任意字符串编码成 JS 字符串字面量（带引号），安全放进 script
    private static func jsString(_ s: String) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: [s]),
              let str = String(data: d, encoding: .utf8), str.count >= 2 else {
            return "\"\""
        }
        return String(str.dropFirst().dropLast())
    }
}

// MARK: - 卡片库

struct CardLibraryView: View {
    @EnvironmentObject var cardStore: CardStore
    @State private var showingLetterEditor = false
    @State private var showingJourneyEditor = false
    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if cardStore.cards.isEmpty {
                    ContentUnavailableView(L("卡片库还是空的"),
                                           systemImage: "rectangle.stack.badge.plus",
                                           description: Text(L("去「做卡片」做第一张吧。")))
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(cardStore.cards) { card in
                                NavigationLink {
                                    CardDetailView(cardID: card.id)
                                } label: {
                                    CardThumbView(card: card)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                    .background(AppTheme.sunny)
                }
            }
            .background(AppTheme.sunny)
            .navigationTitle(L("卡片库"))
            .toolbarBackground(AppTheme.sunny, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingJourneyEditor = true
                    } label: {
                        Label(L("旅程地图"), systemImage: "map")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingLetterEditor = true
                    } label: {
                        Label(L("动画信"), systemImage: "sparkles.tv")
                    }
                }
            }
            .sheet(isPresented: $showingLetterEditor) {
                LetterCardEditorView()
            }
            .sheet(isPresented: $showingJourneyEditor) {
                JourneyCardEditorView()
            }
        }
    }
}

struct CardThumbView: View {
    let card: CardDesign

    var body: some View {
        VStack(spacing: 6) {
            if let img = FileStorage.loadImage(fileName: card.imageFile, subdir: "cards") {
                Image(uiImage: img)
                    .resizable().scaledToFill()
                    .frame(width: 108, height: 144)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.ink, lineWidth: 2))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 108, height: 144)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.ink, lineWidth: 2))
            }
            Text(card.name)
                .font(.caption)
                .lineLimit(1)
        }
    }
}

// MARK: - 开卡仪式

/// 开卡仪式：把存好的整张卡图按面切开，模拟真实开卡——
/// 一张纸 = 整卡轻轻立正；对折 = 先看封面，封面沿右边缘翻开露出整张；四折 = 从 1/4 逐排展开成 2×2。
/// 形式靠图片点尺寸推断（保存时折叠卡存的是整张打开图，比例与宽度是固定值，见 makePanels）。
/// 全文件第二个 3D 旋转变换只许出现在本视图（第一个在做卡页纸组站立变换上），且只此一处：
/// 单张时转整卡（绕 x 轴）、对折时转封面（绕 y 轴），靠 heroAngle/heroAxis/heroAnchor 切换参数共用。
struct CardOpeningView: View {
    let image: UIImage
    private let cols: Int
    private let rows: Int
    private let panels: [UIImage]
    @Environment(\.dismiss) private var dismiss
    /// 仪式阶段：单张 0=倾斜 1=立正；对折 0=只看封面 1=整张浮现+封面翻开中 2=封面消失只剩整张；
    /// 四折 0=只有封面 1=上排展开 2=整张展开
    @State private var stage = 0
    @State private var coverOpen = false
    /// 重播代次：递增会取消上一轮 .task 计时并重新跑仪式
    @State private var runID = 0

    /// 一面的展示宽度：对折整张 = 2 面宽（330），四折整张同宽、四折全高约 440
    private let panelWidth: CGFloat = 165

    init(image: UIImage) {
        self.image = image
        let g = Self.makePanels(from: image)
        self.cols = g.cols
        self.rows = g.rows
        self.panels = g.panels
    }

    private var isBifold: Bool { cols == 2 && rows == 1 }
    private var isQuarter: Bool { cols == 2 && rows == 2 }

    /// 按点尺寸推断拼版：宽高比约 1.5 → 对折整张（660×440）；
    /// 宽高比约 0.75 且宽 ≥1500（像素制式下 1980）→ 四折整张（660×880，与一张纸同比例、靠宽度区分）；
    /// 其余皆按一张纸。裁切按 cgImage 像素逐面切（行优先：四折为 [封面，内页左，内页右，背面]，
    /// 与 CardSheetView 的拼版顺序一致），任何一步失败都回落整图单面。
    private static func makePanels(from image: UIImage) -> (cols: Int, rows: Int, panels: [UIImage]) {
        let size = image.size
        guard size.width > 0, size.height > 0, let cg = image.cgImage else { return (1, 1, [image]) }
        let ratio = size.width / size.height
        var cols = 1
        var rows = 1
        if ratio > 1.2 {
            cols = 2
            rows = 1
        } else if abs(ratio - 0.75) < 0.08 && size.width >= 1500 {
            cols = 2
            rows = 2
        }
        guard cols * rows > 1 else { return (1, 1, [image]) }
        let pw = cg.width / cols
        let ph = cg.height / rows
        var panels: [UIImage] = []
        for r in 0..<rows {
            for c in 0..<cols {
                let rect = CGRect(x: c * pw, y: r * ph,
                                  width: c == cols - 1 ? cg.width - c * pw : pw,
                                  height: r == rows - 1 ? cg.height - r * ph : ph)
                guard let crop = cg.cropping(to: rect) else { return (1, 1, [image]) }
                panels.append(UIImage(cgImage: crop, scale: image.scale,
                                      orientation: image.imageOrientation))
            }
        }
        guard panels.count == cols * rows else { return (1, 1, [image]) }
        return (cols, rows, panels)
    }

    // MARK: 仪式主角（唯一带 3D 旋转的元素）

    private var heroAngle: Double {
        if isBifold { return coverOpen ? -105 : 0 }
        if isQuarter { return 0 }
        return stage == 0 ? 35 : 0
    }

    private var heroAxis: (x: CGFloat, y: CGFloat, z: CGFloat) {
        isBifold ? (x: 0, y: 1, z: 0) : (x: 1, y: 0, z: 0)
    }

    private var heroAnchor: UnitPoint {
        isBifold ? .trailing : .center
    }

    private var heroOffsetX: CGFloat {
        isBifold ? -panelWidth / 2 : 0
    }

    private var heroOpacity: Double {
        (isBifold && stage >= 2) ? 0 : 1
    }

    @ViewBuilder
    private var heroView: some View {
        if isQuarter {
            EmptyView()
        } else if isBifold {
            Image(uiImage: panels[0])
                .resizable().scaledToFit()
                .frame(width: panelWidth)
                .shadow(radius: 6)
        } else {
            Image(uiImage: image)
                .resizable().scaledToFit()
                .frame(width: 280)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(radius: 8)
        }
    }

    /// 四折的展开画面：按阶段切换布局（只有封面 → 上排 → 整张 2×2），阶段间弹簧过渡
    @ViewBuilder
    private var quarterView: some View {
        if stage == 0 {
            panelImage(0)
        } else if stage == 1 {
            HStack(spacing: 4) {
                panelImage(0)
                panelImage(1)
            }
        } else {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    panelImage(0)
                    panelImage(1)
                }
                HStack(spacing: 4) {
                    panelImage(2)
                    panelImage(3)
                }
            }
        }
    }

    private func panelImage(_ idx: Int) -> some View {
        Image(uiImage: panels[idx])
            .resizable().scaledToFit()
            .frame(width: panelWidth)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.94)
                .ignoresSafeArea()
            VStack(spacing: 22) {
                ZStack {
                    if isBifold {
                        // 摊开的整张（底层）：阶段 1 起浮现，封面在它上层翻开
                        Image(uiImage: image)
                            .resizable().scaledToFit()
                            .frame(width: panelWidth * 2)
                            .opacity(stage >= 1 ? 1 : 0)
                    }
                    if isQuarter {
                        quarterView
                    }
                    // 主角在最上层：单张是整卡、对折是封面（四折时为空）
                    heroView
                        .rotation3DEffect(.degrees(heroAngle),
                                          axis: heroAxis,
                                          anchor: heroAnchor,
                                          perspective: 0.55)
                        .scaleEffect(isBifold ? 1 : (stage == 0 ? 0.9 : 1))
                        .opacity(heroOpacity)
                        .offset(x: heroOffsetX)
                        .animation(.easeInOut(duration: 0.85), value: heroAngle)
                        .animation(.easeOut(duration: 0.45), value: heroOpacity)
                        .animation(.easeOut(duration: 0.9), value: stage)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    // 对折在封面阶段点一下也可提前翻开（不等自动计时）
                    if isBifold && stage == 0 { openBifoldCover() }
                }

                Button {
                    runID += 1
                } label: {
                    Label(L("重播"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
            .padding()

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                Spacer()
            }
            .padding()
        }
        .task(id: runID) {
            await runCeremony()
        }
    }

    /// 对折翻封面：整张浮现 + 封面绕右边缘翻开，动画走完后封面淡出、只剩整张
    private func openBifoldCover() {
        stage = 1
        coverOpen = true
        let mine = runID
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            // 重播会递增 runID：旧一轮的计时不能把新一轮的封面提前弄没
            guard mine == runID else { return }
            stage = 2
        }
    }

    private func runCeremony() async {
        stage = 0
        coverOpen = false
        if isBifold {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled, stage == 0 else { return }
            openBifoldCover()
        } else if isQuarter {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { stage = 1 }
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { stage = 2 }
        } else {
            // 单张：稍顿一下就把倾斜回正（角度变化由 heroAngle 的 animation 驱动成 0.9 秒的入场）
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard !Task.isCancelled else { return }
            stage = 1
        }
    }
}

// MARK: - 卡片详情

// MARK: - 帧动画播放

/// 帧动画播放器：一帧帧拍下来的画面按各自在时间线上拖出的时长无限循环（定格动画）。
/// 图与时长由调用方备好：做卡页传内存里的帧，卡片详情传从 frames/ 读回的图与存下的时长。
struct FramePlayerView: View {
    let images: [UIImage]
    let durations: [Double]
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var isPlaying = true

    init(images: [UIImage], durations: [Double] = []) {
        self.images = images
        self.durations = durations
    }

    /// 每帧实际停留秒数：与 images 逐项对齐，缺项/旧存档没存时长的回落 0.35，统一钳 0.1–2.0
    private var effectiveDurations: [Double] {
        images.indices.map { i in
            let d = durations.indices.contains(i) ? durations[i] : 0.35
            return min(max(d, 0.1), 2.0)
        }
    }

    private var totalDuration: Double {
        effectiveDurations.reduce(0, +)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.94)
                .ignoresSafeArea()
            VStack(spacing: 22) {
                if images.indices.contains(index) {
                    Image(uiImage: images[index])
                        .resizable().scaledToFit()
                        .frame(maxWidth: .infinity)
                }
                Text(images.isEmpty ? "0 / 0" : "\(index + 1) / \(images.count)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                // 只读进度条：同一条时间线的缩影，块宽 ∝ 该帧时长（整条约 300 pt）；
                // 已播过的帧近全白、当前帧主题色、没到的帧淡白
                if totalDuration > 0 {
                    HStack(spacing: 2) {
                        ForEach(images.indices, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(i == index ? Color.accentColor
                                      : (i < index ? Color.white.opacity(0.9)
                                         : Color.white.opacity(0.25)))
                                .frame(width: CGFloat(effectiveDurations[i]) * CGFloat(300.0 / totalDuration),
                                       height: 10)
                        }
                    }
                }
                HStack(spacing: 16) {
                    Button {
                        isPlaying.toggle()
                    } label: {
                        Label(isPlaying ? L("暂停") : L("播放"),
                              systemImage: isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
            }
            .padding()

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                Spacer()
            }
            .padding()
        }
        .preferredColorScheme(.dark)
        .task(id: isPlaying) {
            // 暂停/继续会取消旧循环、新循环从当前帧接着走；暂停时循环条件不成立直接退出。
            // 每帧睡自己的时长（时间线上拖出来的），不再有全局速度
            while isPlaying && images.count > 1 {
                let d = effectiveDurations.indices.contains(index) ? effectiveDurations[index] : 0.35
                try? await Task.sleep(nanoseconds: UInt64(d * 1_000_000_000))
                if Task.isCancelled { return }
                index = (index + 1) % images.count
            }
        }
    }
}

struct CardDetailView: View {
    @EnvironmentObject var cardStore: CardStore
    @EnvironmentObject var contactStore: ContactStore
    @Environment(\.dismiss) private var dismiss
    let cardID: UUID
    @State private var sendDate = Date().addingTimeInterval(3600)
    @State private var message: String? = nil
    @State private var showingDeleteConfirm = false
    @State private var showingLetterPlayer = false
    @State private var showingJourneyPlayer = false
    @State private var showingCardOpening = false
    @State private var showingFramePlayer = false
    /// 点「播放动画」时现从 frames/ 读回的帧图（凑不齐 2 张就不打开播放器）
    @State private var frameImages: [UIImage] = []
    /// 与 frameImages 逐项对齐的每帧时长（读图时按同一序号取 frameDurations，丢图的帧时长一起跳过）
    @State private var frameLoadedDurations: [Double] = []

    private var card: CardDesign? {
        cardStore.cards.first { $0.id == cardID }
    }

    var body: some View {
        Group {
            if let card = card {
                ScrollView {
                    VStack(spacing: 16) {
                        if let img = FileStorage.loadImage(fileName: card.imageFile, subdir: "cards") {
                            Image(uiImage: img)
                                .resizable().scaledToFit()
                                .frame(maxWidth: 300)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .shadow(radius: 5)
                        } else {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.secondary.opacity(0.12))
                                .frame(width: 240, height: 320)
                                .overlay {
                                    VStack(spacing: 6) {
                                        Image(systemName: "photo.slash").font(.largeTitle)
                                        Text(L("图片文件已丢失")).font(.caption)
                                    }
                                    .foregroundStyle(.secondary)
                                }
                        }
                        Text(card.name).font(.headline)

                        if imageExists(for: card) {
                            Button {
                                showingCardOpening = true
                            } label: {
                                Label(L("打开卡片"), systemImage: "envelope.open")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SunnyButtonStyle())
                        }

                        if card.frameFiles.count >= 2 {
                            Button {
                                // 先把帧图读回来，凑不齐 2 张就不打开（帧图可能已丢失）；
                                // 图与时长按同一序号成对取，丢图的帧把它的时长也一起跳过、保持对齐
                                var imgs: [UIImage] = []
                                var durs: [Double] = []
                                for (i, fileName) in card.frameFiles.enumerated() {
                                    if let img = FileStorage.loadImage(fileName: fileName, subdir: "frames") {
                                        imgs.append(img)
                                        durs.append(card.frameDurations.indices.contains(i)
                                                    ? card.frameDurations[i] : 0.35)
                                    }
                                }
                                if imgs.count >= 2 {
                                    frameImages = imgs
                                    frameLoadedDurations = durs
                                    showingFramePlayer = true
                                }
                            } label: {
                                Label(L("播放动画"), systemImage: "film")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(InkButtonStyle())
                        }

                        if let raw = card.packageKind,
                           let pkg = PackageKind(rawValue: raw), pkg != .none {
                            VStack(spacing: 6) {
                                Text(L("包装")).font(.subheadline).bold()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                PackageStageView(
                                    kind: pkg,
                                    envelopeStyle: EnvelopeStyle(rawValue: card.packageStyle ?? "") ?? .cream,
                                    boxStyle: BoxStyle(rawValue: card.packageStyle ?? "") ?? .purple,
                                    cardImage: FileStorage.loadImage(fileName: card.imageFile, subdir: "cards"),
                                    decorations: card.decorations ?? [])
                                    .background(Color.secondary.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }

                        if card.letter != nil {
                            Button {
                                showingLetterPlayer = true
                            } label: {
                                Label(L("播放动画信"), systemImage: "play.rectangle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SunnyButtonStyle())
                        }

                        if card.journey != nil {
                            Button {
                                showingJourneyPlayer = true
                            } label: {
                                Label(L("开始旅程"), systemImage: "figure.walk")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SunnyButtonStyle())
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("归入卡片池")).font(.subheadline).bold()
                            Picker(L("送给"), selection: Binding(
                                get: { card.assignedContactID },
                                set: { newID in
                                    updateAssignment(card: card, to: newID)
                                }
                            )) {
                                Text(L("不指定")).tag(UUID?.none)
                                ForEach(contactStore.contacts) { contact in
                                    Text(contact.name).tag(UUID?.some(contact.id))
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("定时发送（提醒）")).font(.subheadline).bold()
                            Text(L("v1 先用提醒的方式：到时间通知你来发送这张卡。"))
                                .font(.caption).foregroundStyle(.secondary)
                            DatePicker(L("发送时间"), selection: $sendDate,
                                       in: Date()..., displayedComponents: [.date, .hourAndMinute])
                            Button {
                                NotificationManager.shared.scheduleSendReminder(
                                    card: card,
                                    contact: contactStore.contact(id: card.assignedContactID),
                                    at: sendDate
                                ) { ok in
                                    message = ok ? L("已设好提醒，到时间会通知你发送。") : L("设置提醒失败，请确认已允许通知。")
                                }
                            } label: {
                                Label(L("在这个时间提醒我发送"), systemImage: "bell.badge")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if imageExists(for: card) {
                            ShareLink(item: FileStorage.url(for: card.imageFile, subdir: "cards")) {
                                Label(L("分享这张卡片"), systemImage: "square.and.arrow.up")
                            }
                        }

                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Label(L("删除卡片"), systemImage: "trash")
                        }
                    }
                    .padding()
                }
                .background(AppTheme.sunny)
                .toolbarBackground(AppTheme.sunny, for: .navigationBar)
                .toolbarBackgroundVisibility(.visible, for: .navigationBar)
                .navigationTitle(L("卡片详情"))
                .fullScreenCover(isPresented: $showingLetterPlayer) {
                    if let letter = card.letter {
                        LetterPlayerView(data: letter)
                    }
                }
                .fullScreenCover(isPresented: $showingJourneyPlayer) {
                    if let journey = card.journey {
                        JourneyPlayerView(journey: journey)
                    }
                }
                .fullScreenCover(isPresented: $showingCardOpening) {
                    if let img = FileStorage.loadImage(fileName: card.imageFile, subdir: "cards") {
                        CardOpeningView(image: img)
                    }
                }
                .fullScreenCover(isPresented: $showingFramePlayer) {
                    FramePlayerView(images: frameImages, durations: frameLoadedDurations)
                }
                .alert(L("删除卡片"), isPresented: $showingDeleteConfirm) {
                    Button(L("取消"), role: .cancel) {}
                    Button(L("删除"), role: .destructive) {
                        removeFromPools(card: card)
                        cardStore.delete(card)
                        dismiss()
                    }
                } message: {
                    Text(String(format: L("确定要删除「%@」吗？图片文件也会一起删掉。"), card.name))
                }
                .alert(L("提示"), isPresented: Binding(
                    get: { message != nil },
                    set: { if !$0 { message = nil } }
                )) {
                    Button(L("好")) { message = nil }
                } message: {
                    Text(message ?? "")
                }
            } else {
                ContentUnavailableView(L("卡片不存在"), systemImage: "rectangle.slash")
            }
        }
    }

    private func imageExists(for card: CardDesign) -> Bool {
        guard !card.imageFile.isEmpty else { return false }
        let url = FileStorage.url(for: card.imageFile, subdir: "cards")
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
    }

    private func updateAssignment(card: CardDesign, to newID: UUID?) {
        var updated = card
        let oldID = updated.assignedContactID
        updated.assignedContactID = newID
        cardStore.update(updated)
        if let old = oldID, var oldContact = contactStore.contact(id: old) {
            oldContact.cardPoolIDs.removeAll { $0 == card.id }
            contactStore.update(oldContact)
        }
        if let new = newID, var newContact = contactStore.contact(id: new) {
            if !newContact.cardPoolIDs.contains(card.id) {
                newContact.cardPoolIDs.append(card.id)
                contactStore.update(newContact)
            }
        }
    }

    private func removeFromPools(card: CardDesign) {
        if let ownerID = card.assignedContactID,
           var owner = contactStore.contact(id: ownerID) {
            owner.cardPoolIDs.removeAll { $0 == card.id }
            contactStore.update(owner)
        }
    }
}

// MARK: - 设置

struct SettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var contactStore: ContactStore
    @EnvironmentObject var cardStore: CardStore
    @AppStorage("appLanguage") private var appLanguage: String = AppLanguage.zh.rawValue
    @State private var authStatusText = L("未查询")
    @State private var calendarMessage: String? = nil
    /// 正在给哪个分组挑默认卡（非 nil 时弹出选择器）
    @State private var defaultPickerGroup: ContactGroup? = nil

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = settingsStore.settings.reminderHour
                comps.minute = settingsStore.settings.reminderMinute
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                settingsStore.settings.reminderHour = comps.hour ?? 9
                settingsStore.settings.reminderMinute = comps.minute ?? 0
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("语言 / Language", selection: $appLanguage) {
                        Text("中文版").tag(AppLanguage.zh.rawValue)
                        Text("English").tag(AppLanguage.en.rawValue)
                    }
                } header: {
                    Text("语言 / Language")
                        .foregroundStyle(AppTheme.ink)
                }
                .chunkyRow()

                Section {
                    Picker(L("普通联系人提前提醒"), selection: $settingsStore.settings.advanceDays) {
                        ForEach(ReminderSettings.advanceOptions, id: \.self) { d in
                            Text(d == 0 ? L("当天") : String(format: L("提前 %d 天"), d)).tag(d)
                        }
                    }
                    Picker(L("星标联系人提前提醒"), selection: $settingsStore.settings.starredAdvanceDays) {
                        ForEach(ReminderSettings.advanceOptions, id: \.self) { d in
                            Text(d == 0 ? L("当天") : String(format: L("提前 %d 天"), d)).tag(d)
                        }
                    }
                    DatePicker(L("每天提醒时间"), selection: timeBinding,
                               displayedComponents: .hourAndMinute)
                    Toggle(L("持续提醒"), isOn: $settingsStore.settings.nagEnabled)
                    if settingsStore.settings.nagEnabled {
                        Picker(L("重复提醒间隔"), selection: $settingsStore.settings.nagIntervalHours) {
                            ForEach(ReminderSettings.nagIntervalOptions, id: \.self) { h in
                                Text(String(format: L("每 %d 小时"), h)).tag(h)
                            }
                        }
                        Text(L("开启后，如果一直没有确认，生日提醒会按所选间隔反复发送，直到你点通知上的「已祝福，停止提醒」，或点开通知进入 App 为止。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text(L("提醒设置"))
                        .foregroundStyle(AppTheme.ink)
                } footer: {
                    Text(L("改完设置会自动重新安排所有生日提醒。"))
                }
                .chunkyRow()

                Section {
                    ForEach(ContactGroup.allCases) { group in
                        Picker(L(group.rawValue), selection: modeBinding(for: group)) {
                            ForEach(SendMode.allCases) { mode in
                                Text(L(mode.rawValue)).tag(mode)
                            }
                        }
                    }
                } header: {
                    Text(L("每个分组的发送方式"))
                        .foregroundStyle(AppTheme.ink)
                } footer: {
                    Text(L("「自动发送（模拟）」在 v1 里仍是提醒，只是提醒文案会注明模拟自动发送；真正的自动发送等接了邮件/短信通道再开。"))
                }
                .chunkyRow()

                Section {
                    ForEach(ContactGroup.allCases) { group in
                        Button {
                            defaultPickerGroup = group
                        } label: {
                            HStack {
                                Text(L(group.rawValue))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if let card = settingsStore.groupDefaultCard(for: group, cardStore: cardStore) {
                                    Text(card.name)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                } else {
                                    Text(L("未设置"))
                                        .foregroundStyle(.secondary)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                } header: {
                    Text(L("分组默认卡"))
                        .foregroundStyle(AppTheme.ink)
                } footer: {
                    Text(L("给每个分组选一张现成的卡。组里谁过生日、又没单独给他准备卡，就用这张。"))
                }
                .chunkyRow()

                Section(L("通知权限")) {
                    LabeledContent(L("当前状态"), value: authStatusText)
                    Button(L("请求通知权限")) {
                        NotificationManager.shared.requestAuthorization { granted in
                            authStatusText = granted ? L("已允许") : L("未允许")
                            if granted { reschedule() }
                        }
                    }
                    Button(L("重新安排全部提醒")) { reschedule() }
                }
                .chunkyRow()

                Section(L("系统日历")) {
                    Button(L("把所有生日加进系统日历")) {
                        CalendarManager.shared.addAllBirthdays(contacts: contactStore.contacts) { msg in
                            calendarMessage = msg
                        }
                    }
                    Text(L("每个生日会建成每年重复的日历事件；已存在的会跳过，不重复添加。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .chunkyRow()

                Section(L("关于")) {
                    LabeledContent(L("版本"), value: L("v0.1（本机版）"))
                    Text(L("联系人、卡片和设置都只存在这台手机里，不上传任何服务器。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .chunkyRow()
            }
            .sunnyScreen()
            .navigationTitle(L("设置"))
            .toolbarBackground(AppTheme.sunny, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .onAppear {
                NotificationManager.shared.authorizationStatus { status in
                    switch status {
                    case .authorized: authStatusText = L("已允许")
                    case .denied: authStatusText = L("已被拒绝（去系统设置打开）")
                    case .notDetermined: authStatusText = L("还没询问过")
                    case .provisional: authStatusText = L("临时允许")
                    case .ephemeral: authStatusText = L("临时会话")
                    @unknown default: authStatusText = L("未知")
                    }
                }
            }
            .onChange(of: settingsStore.settings) { _, _ in
                reschedule()
            }
            .sheet(item: $defaultPickerGroup) { group in
                GroupDefaultCardPickerView(group: group)
            }
            .alert(L("日历"), isPresented: Binding(
                get: { calendarMessage != nil },
                set: { if !$0 { calendarMessage = nil } }
            )) {
                Button(L("好")) { calendarMessage = nil }
            } message: {
                Text(calendarMessage ?? "")
            }
        }
    }

    private func modeBinding(for group: ContactGroup) -> Binding<SendMode> {
        Binding(
            get: { settingsStore.settings.mode(for: group) },
            set: { newMode in
                settingsStore.settings.groupModes[group.rawValue] = newMode.rawValue
            }
        )
    }

    private func reschedule() {
        NotificationManager.shared.reschedule(contacts: contactStore.contacts,
                                              settings: settingsStore.settings)
    }
}
