import Foundation

/// The cats that ship with im, in the same JSON format as custom cats in `~/.im/cats/`.
public enum BuiltinCats {
    public static let defaultID = "calico"

    public static let all: [CatSkin] = sources.map { try! CatSkin(id: $0.id, json: Data($0.json.utf8)) }

    static let sources: [(id: String, json: String)] = [
        ("calico", """
        {
          "name": "Calico",
          "names": { "zh-Hans": "三花" },
          "palette": { "k": "#2A211E", "w": "#FAF6F0", "o": "#E88C3A", "d": "#342C2A", "g": "#8DB43C", "h": "#FFFFFF", "p": "#E896A0" },
          "awake": [
            "..kk..........kk..",
            ".kook........kddk.",
            ".kopok......kdpdk.",
            ".kooookkkkkkddddk.",
            "kooooooowwdddddddk",
            "koooooowwwwddddddk",
            "kwwwhgwwwwwwhgdddk",
            "kwwwggwwwwwwggwwwk",
            "kwwwwwwwwwwwwwwwwk",
            "kwwwwwwwppwwwwwwwk",
            "kwwwwwwkwwkwwwwwwk",
            "kwwwwwwwkkwwwwwwwk",
            "kwwwwwwwwwwwwwwwwk",
            ".kwwwwwwwwwwwwwwk.",
            "kwkwwwwwwwwwwwwkwk",
            ".k.kkwwwwwwwwkk.k.",
            ".....kkkkkkkk....."
          ],
          "blink": [
            "..kk..........kk..",
            ".kook........kddk.",
            ".kopok......kdpdk.",
            ".kooookkkkkkddddk.",
            "kooooooowwdddddddk",
            "koooooowwwwddddddk",
            "kwwwwwwwwwwwwwdddk",
            "kwwwkkwwwwwwkkwwwk",
            "kwwwwwwwwwwwwwwwwk",
            "kwwwwwwwppwwwwwwwk",
            "kwwwwwwkwwkwwwwwwk",
            "kwwwwwwwkkwwwwwwwk",
            "kwwwwwwwwwwwwwwwwk",
            ".kwwwwwwwwwwwwwwk.",
            "kwkwwwwwwwwwwwwkwk",
            ".k.kkwwwwwwwwkk.k.",
            ".....kkkkkkkk....."
          ]
        }
        """),
        ("blue", """
        {
          "name": "British Blue",
          "names": { "zh-Hans": "蓝猫" },
          "palette": { "k": "#3A4250", "g": "#8A97AA", "l": "#B4BDCB", "e": "#E89A38", "h": "#FFFFFF", "p": "#C9A9B0", "n": "#6E7688" },
          "awake": [
            "..kk..........kk..",
            ".kggk........kggk.",
            ".kgpgk......kgpgk.",
            ".kggggkkkkkkggggk.",
            "kggggggggggggggggk",
            "kggggggggggggggggk",
            "kggghegggggghegggk",
            "kgggeeggggggeegggk",
            "kggggggggggggggggk",
            "kgggggllnnllgggggk",
            "kggggglkllklgggggk",
            "kgggggllkkllgggggk",
            "kggggggllllggggggk",
            ".kggggggggggggggk.",
            "kgkggggggggggggkgk",
            ".k.kkggggggggkk.k.",
            ".....kkkkkkkk....."
          ],
          "blink": [
            "..kk..........kk..",
            ".kggk........kggk.",
            ".kgpgk......kgpgk.",
            ".kggggkkkkkkggggk.",
            "kggggggggggggggggk",
            "kggggggggggggggggk",
            "kggggggggggggggggk",
            "kgggkkggggggkkgggk",
            "kggggggggggggggggk",
            "kgggggllnnllgggggk",
            "kggggglkllklgggggk",
            "kgggggllkkllgggggk",
            "kggggggllllggggggk",
            ".kggggggggggggggk.",
            "kgkggggggggggggkgk",
            ".k.kkggggggggkk.k.",
            ".....kkkkkkkk....."
          ]
        }
        """),
        ("orange", """
        {
          "name": "Orange Tabby",
          "names": { "zh-Hans": "橘猫" },
          "palette": { "k": "#4A2C18", "o": "#F2A24A", "s": "#C86E28", "w": "#FFF6EA", "e": "#9CC23C", "h": "#FFFFFF", "p": "#F09AA6" },
          "awake": [
            "..kk..........kk..",
            ".kook........kook.",
            ".kopok......kopok.",
            ".kooookkkkkkooook.",
            "kooooosossosoooook",
            "kooooooossoooooook",
            "koooheooooooheoook",
            "koooeeooooooeeoook",
            "kssoooowwwwoooossk",
            "kooooowwppwwoooook",
            "kssooowkwwkwooossk",
            "koooooowkkwooooook",
            "kooooowwwwwwoooook",
            ".koooowwwwwwooook.",
            "kokooooooooooookok",
            ".k.kkooooooookk.k.",
            ".....kkkkkkkk....."
          ],
          "blink": [
            "..kk..........kk..",
            ".kook........kook.",
            ".kopok......kopok.",
            ".kooookkkkkkooook.",
            "kooooosossosoooook",
            "kooooooossoooooook",
            "kooooooooooooooook",
            "koookkooooookkoook",
            "kssoooowwwwoooossk",
            "kooooowwppwwoooook",
            "kssooowkwwkwooossk",
            "koooooowkkwooooook",
            "kooooowwwwwwoooook",
            ".koooowwwwwwooook.",
            "kokooooooooooookok",
            ".k.kkooooooookk.k.",
            ".....kkkkkkkk....."
          ]
        }
        """),
        ("ragdoll", """
        {
          "name": "Ragdoll",
          "names": { "zh-Hans": "布偶" },
          "palette": { "k": "#3A2820", "d": "#6E503E", "w": "#F6F0E6", "b": "#468CE6", "h": "#FFFFFF", "p": "#E896A0" },
          "awake": [
            "..kk..........kk..",
            ".kddk........kddk.",
            ".kdpdk......kdpdk.",
            ".kddddkkkkkkddddk.",
            "kdddddddwwdddddddk",
            "kddddddwwwwddddddk",
            "kdddhbdwwwwdhbdddk",
            "kdddbbwwwwwwbbdddk",
            "kddddwwwwwwwwddddk",
            "kdddwwwwppwwwwdddk",
            "kddwwwwkwwkwwwwddk",
            "kwwwwwwwkkwwwwwwwk",
            "kwwwwwwwwwwwwwwwwk",
            ".kwwwwwwwwwwwwwwk.",
            "kwkwwwwwwwwwwwwkwk",
            ".k.kkwwwwwwwwkk.k.",
            ".....kkkkkkkk....."
          ],
          "blink": [
            "..kk..........kk..",
            ".kddk........kddk.",
            ".kdpdk......kdpdk.",
            ".kddddkkkkkkddddk.",
            "kdddddddwwdddddddk",
            "kddddddwwwwddddddk",
            "kddddddwwwwddddddk",
            "kdddkkwwwwwwkkdddk",
            "kddddwwwwwwwwddddk",
            "kdddwwwwppwwwwdddk",
            "kddwwwwkwwkwwwwddk",
            "kwwwwwwwkkwwwwwwwk",
            "kwwwwwwwwwwwwwwwwk",
            ".kwwwwwwwwwwwwwwk.",
            "kwkwwwwwwwwwwwwkwk",
            ".k.kkwwwwwwwwkk.k.",
            ".....kkkkkkkk....."
          ]
        }
        """),
        ("american-shorthair", """
        {
          "name": "American Shorthair",
          "names": { "zh-Hans": "美短" },
          "palette": { "k": "#26262A", "l": "#C9CDD2", "d": "#3A3A40", "w": "#F2F2F0", "e": "#7DB43A", "h": "#FFFFFF", "p": "#C87A70" },
          "awake": [
            "..kk..........kk..",
            ".kllk........kllk.",
            ".klplk......klplk.",
            ".kllllkkkkkkllllk.",
            "klllldldlldldllllk",
            "klllldllddlldllllk",
            "kdllhellllllhelldk",
            "kllleelllllleelllk",
            "kddllllwwwwllllddk",
            "klllllwwppwwlllllk",
            "kddlllwkwwkwlllddk",
            "klllllwwkkwwlllllk",
            "kllllllwwwwllllllk",
            ".kllllllllllllllk.",
            "klkllllllllllllklk",
            ".k.kkllllllllkk.k.",
            ".....kkkkkkkk....."
          ],
          "blink": [
            "..kk..........kk..",
            ".kllk........kllk.",
            ".klplk......klplk.",
            ".kllllkkkkkkllllk.",
            "klllldldlldldllllk",
            "klllldllddlldllllk",
            "kdlllllllllllllldk",
            "klllkkllllllkklllk",
            "kddllllwwwwllllddk",
            "klllllwwppwwlllllk",
            "kddlllwkwwkwlllddk",
            "klllllwwkkwwlllllk",
            "kllllllwwwwllllllk",
            ".kllllllllllllllk.",
            "klkllllllllllllklk",
            ".k.kkllllllllkk.k.",
            ".....kkkkkkkk....."
          ]
        }
        """),
    ]
}
