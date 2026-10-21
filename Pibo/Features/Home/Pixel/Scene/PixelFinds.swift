import Foundation

// The small things Pibo brings back from exploring (decision 058), in Core's item order.
// Each is a 7×7 stamp; Pibo carries it in front of its belly and the shelf shows it larger.
//
// Ported from HarmonyPibo `pixel/scene/PixelFinds.ets`.

private let FINDS: [[String]] = [
    ["..DD...", ".hHhH..", "HhHhHh.", ".hHhH..", "HhHhHh.", ".hHhH..", "..hh..."], // pinecone
    ["......j", "....jjJ", "...jjJ.", "..jjJ..", ".jjJ...", ".jJ....", "D......"], // feather
    ["..qqq..", ".qQqqq.", "qqqqQqq", "qQqqqqQ", ".qqqQq.", "..QQq..", "......."], // odd stone
    ["...p...", "..ppp..", ".pPppp.", "ppppPpp", ".ppPpp.", "...D...", "...D..."], // red leaf
    ["..DD...", ".HHHH..", "HHHHHH.", ".hhhh..", ".hhhh..", "..hh...", "......."], // acorn
    [".gg.gg.", "gllggl.", ".gggg..", "gglgg..", ".gg.gg.", "...G...", "...G..."], // four-leaf clover
    [".j.j.j.", "j.jjj.j", ".jjjjj.", "j.jjj.j", ".j.G.j.", "...G...", "...G..."], // dandelion
    ["..hhh..", ".hHHHh.", "hHhhhHh", "hHhHhHh", ".hhHhh.", "mmmmmm.", "......."], // snail shell
    ["......D", ".....D.", "..DdD..", ".D.D...", "D..D...", "..D....", ".D....."], // twig
    [".xxxx..", "xxjxxx.", "xxxxjx.", ".jjjj..", "..jj...", "..jj...", "......."], // little mushroom
    [".......", "..qqq..", ".qqqqq.", "qqqqqqQ", ".qqqqQ.", "..QQQ..", "......."], // smooth pebble
    ["...j...", "..jjj..", ".jJjJj.", "jJjJjJj", "jjjjjjj", ".jjjjj.", "......."], // river shell
    ["..hh...", ".hHHh..", "hHhhHh.", ".hHHh..", "h.hh.h.", ".h..h..", "......."], // cicada shell
    ["zzzzzzz", ".zZzZz.", ".zZ.Zz.", "..Z.Z..", "..Z..Z.", "..Z....", "......."], // icicle
    [".......", "..iii..", ".iiiiI.", "iiiiiII", "iiiiIII", ".iiIII.", "..III.."], // snowball
    ["..g....", ".Gg....", ".bbb.b.", "bbbbbbb", ".bbbbb.", "..bbb..", "......."], // wild berry
    [".......", "..FF...", ".FFFF..", "FFFFFF.", ".FFFFF.", "..FFF..", "...F..."], // petal
    [".......", "..jjj..", ".jjjJj.", "jJ.j.Jj", "jjjjjjj", ".jjjjj.", "......."], // eggshell
    [".......", ".uuuuu.", "uuuuuuu", ".uuuuu.", "..u.u..", "...D...", "...D..."], // ginkgo leaf
    [".DDDDD.", ".jZZZj.", "jZ.Z.Zj", "jZZ.ZZj", "jZ.Z.Zj", "jZZZZZj", ".jjjjj."], // a jar of wind
    [".......", ".qq.qq.", "qqqqqqq", "qqqqqqQ", ".qqqqQ.", ".......", "......."], // cloud stone
    ["G.G.G..", ".G.G.G.", "G.G.G..", ".GGGG..", "..DD...", "..DD...", "......."], // pine needles
    ["..u.u..", ".uuuuu.", "..uuu..", ".uuuuu.", "..uuu..", "...D...", "...D..."], // wheat ear
    [".......", "..ZZ...", ".ZZzZ..", "ZzZZzZ.", ".ZZzZZ.", "..ZZZ..", "......."] // sea glass
]

// The season's story things (decision 059), outside Core's find order: the seed from the
// pod, the pod's lost screw, Pibo's rolled-up report and a letter from home.
let PIXEL_STORY_SEED: Int = 100
let PIXEL_STORY_SCREW: Int = 101
let PIXEL_STORY_REPORT: Int = 102
let PIXEL_STORY_LETTER: Int = 103
// Season two, "小溪那边": a bridge plank and the old notebook from across the creek.
let PIXEL_STORY_PLANK: Int = 104
let PIXEL_STORY_NOTEBOOK: Int = 105

private let STORY_FINDS: [[String]] = [
    [".......", "...g...", "..hHh..", ".hHHHh.", ".hHhHh.", "..hhh..", "......."], // the seed, already sprouting
    [".......", ".qLLq..", "..QqQ..", "...Q...", "...q...", "...Q...", "...q..."], // the screw
    [".......", "jjjjjj.", "jOOjOj.", "jjjjjjD", "jOjOOj.", "jjjjjj.", "......."], // the report
    [".......", "jjjjjjj", "jJ...Jj", "jjJ.Jjj", "jjjpjjj", "jjjjjjj", "......."], // a letter, sealed red
    [".......", ".......", "ddddddd", "MMQMMQM", "DDDDDDD", ".......", "......."], // a plank
    [".......", "5JJJJJ.", "J3O3OJ.", "J3OO3J5", "J3O3OJ.", "5JJJJJ.", "......."] // the old notebook, mossy
]

let PIXEL_FIND_SIZE: Int = 7

func pixelFindCount() -> Int {
    FINDS.count
}

func pixelFindRows(_ item: Int) -> [String] {
    if item >= PIXEL_STORY_SEED {
        let index = item - PIXEL_STORY_SEED
        return STORY_FINDS.indices.contains(index) ? STORY_FINDS[index] : FINDS[0]
    }
    return FINDS.indices.contains(item) ? FINDS[item] : FINDS[0]
}

/// Draws a find with its top-left at (x, y). Unknown ids draw nothing.
func drawPixelFind(_ frame: PixelFrame, _ item: Int, _ x: Int, _ y: Int) {
    if item >= PIXEL_STORY_SEED && item < PIXEL_STORY_SEED + STORY_FINDS.count {
        frame.stamp(STORY_FINDS[item - PIXEL_STORY_SEED], x, y)
        return
    }
    if item < 0 || item >= FINDS.count { return }
    frame.stamp(FINDS[item], x, y)
}

/// The shelf's silhouette for a find not brought home yet.
func drawPixelFindSilhouette(_ frame: PixelFrame, _ item: Int, _ x: Int, _ y: Int, _ ink: PixelInk) {
    let rows = pixelFindRows(item)
    for (dy, row) in rows.enumerated() {
        for (dx, glyph) in row.enumerated() where glyph != "." {
            frame.set(x + dx, y + dy, ink)
        }
    }
}
