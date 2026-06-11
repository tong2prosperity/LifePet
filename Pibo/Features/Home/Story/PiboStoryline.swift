import SwiftUI
import Observation

// MARK: - Pibo 故事线 (app 叙事 — 拍一拍掉线索)
//
// The app tells Pibo's story in fragments: patting Pibo sometimes shakes loose
// the **next clue of the current chapter** instead of a state-pool line. Clues
// are sequential (the narrative unfolds in order), persisted per install, and
// reset together with the pet.
//
// ⚠️ Narrative scope is still being defined (多数剧情未定). What ships now:
//   - the data model (chapter → ordered clues),
//   - chapter 1 (魔丸期 · 坠落) authored in the garbled 魔丸 voice,
//   - sequential reveal via `pat()` + persistence.
// Stubs / TODO for the later pass:
//   - chapter gating tied to growth / day count (`StoryChapter.isUnlocked`),
//   - a journal surface to re-read collected clues (`StoryJournalView`),
//   - clue-specific art / bubble treatment beyond the accent border.

/// One fragment of the narrative, spoken by Pibo in its garbled voice.
struct StoryClue: Identifiable, Equatable {
    let id: String
    /// The garbled spoken line (what the speech bubble shows).
    let line: String
}

/// An ordered run of clues. Chapters unlock sequentially; within a chapter
/// clues reveal in order (a story, not a gacha pool).
struct StoryChapter: Identifiable, Equatable {
    let id: String
    let title: String
    let clues: [StoryClue]
    /// TODO(narrative): real gating (growth stage / day count / 能量 milestones).
    /// For now only the first chapter is open.
    var isUnlocked: Bool = false
}

/// Authored narrative content. Pure data — the reveal cursor lives in
/// `PiboStorylineStore`.
enum PiboStoryline {
    /// 第一章 · 坠落 — how Pibo got here, told sideways. 魔丸语气:
    /// garbled-but-readable fragments, subject = Pibo/花, the odd 啵/呢.
    static let chapters: [StoryChapter] = [
        StoryChapter(
            id: "ch1-fall",
            title: "坠落",
            clues: [
                StoryClue(id: "ch1-1", line: "...黑的洞...不是洞...是门啵..."),
                StoryClue(id: "ch1-2", line: "...掉下来...那晚...花...抓不住风..."),
                StoryClue(id: "ch1-3", line: "...那边的天...是两层的...呢..."),
                StoryClue(id: "ch1-4", line: "...花的名字...只有花...知道..."),
                StoryClue(id: "ch1-5", line: "...花开了...门...就会再开...啵..."),
            ],
            isUnlocked: true
        ),
        // TODO(narrative): 第二章 · 花的秘密 — unlocks后期; copy 未定.
        StoryChapter(
            id: "ch2-flower",
            title: "花的秘密",
            clues: []
        ),
    ]
}

/// Reveal-progress store: how many clues the user has shaken loose, persisted
/// across launches. `@Observable` so a future journal view can list
/// `revealedClues` live.
@MainActor
@Observable
final class PiboStorylineStore {
    private static let revealedKey = "pibo.story.revealedCount.v1"

    /// Count of clues revealed so far, across chapters in order.
    private(set) var revealedCount: Int

    init() {
        revealedCount = UserDefaults.standard.integer(forKey: Self.revealedKey)
    }

    /// All clues in narrative order, across unlocked chapters.
    private var orderedClues: [StoryClue] {
        PiboStoryline.chapters.filter(\.isUnlocked).flatMap(\.clues)
    }

    /// Clues already revealed — for the future journal UI.
    var revealedClues: [StoryClue] { Array(orderedClues.prefix(revealedCount)) }

    /// Whether another clue is waiting to be discovered.
    var hasUnrevealedClue: Bool { revealedCount < orderedClues.count }

    /// Reveal and return the next clue, advancing the cursor. `nil` when the
    /// unlocked chapters are exhausted.
    func revealNextClue() -> StoryClue? {
        let clues = orderedClues
        guard revealedCount < clues.count else { return nil }
        let clue = clues[revealedCount]
        revealedCount += 1
        UserDefaults.standard.set(revealedCount, forKey: Self.revealedKey)
        return clue
    }

    /// Back to an untold story (new pet / 重置).
    func reset() {
        revealedCount = 0
        UserDefaults.standard.removeObject(forKey: Self.revealedKey)
    }
}

// MARK: - Journal stub

/// TODO(narrative + design): the surface where collected clues are re-read —
/// likely a page of the 图鉴 or a long-press on Pibo. Not routed anywhere yet;
/// kept compiling so the seam is visible.
struct StoryJournalView: View {
    @Environment(PetStateStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LP.Spacing.m) {
                Text(AppLocalization.text("Pibo 的碎片"))
                    .lpText(LP.Typography.uiH4)
                    .foregroundStyle(LP.Content.primary)
                ForEach(store.story.revealedClues) { clue in
                    Text(clue.line)
                        .lpText(LP.Typography.b2Regular)
                        .foregroundStyle(LP.Content.secondary)
                }
                if store.story.hasUnrevealedClue {
                    Text(AppLocalization.text("…还有没说完的。多拍拍它。"))
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(LP.Content.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LP.Spacing.l)
        }
        .background(LP.Fill.bgSurface)
    }
}
