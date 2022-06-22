import Nat8 "mo:base/Nat8";
import Text "mo:base/Text";

import Backgrounds "./elements/backgrounds";
import Capes "./elements/capes";
import Classes "./elements/classes";
import Eyes "./elements/eyes";
import Hair "./elements/hair";
import Hoods "./elements/hoods";
import MagicRings "./elements/magic_rings";
import OgBadge "./elements/og_badge";
import Outfits "./elements/outfits";
import Scar "./elements/scar";
import Skins "./elements/skins";
import Weapons "./elements/weapons";
// END TODO

// order of assets

module {
  public func make(seed : [Nat8]) : Text {
    var svg : Text = "<?xml version=\"1.0\" encoding=\"utf-8\"?><svg version=\"1.1\" id=\"generated\" xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" x=\"0px\" y=\"0px\" viewBox=\"0 0 300 300\" xml:space=\"preserve\">";
    // background
    // class badge
    // outfit
    // skin
    // scar
    // eyes
    // hair
    // hood
    // magic ring
    // cape
    // weapon
    // og badge
    svg #= "<g id=\"backgrounds\"><image href=\""#Backgrounds.elements[Nat8.toNat(seed[0])]#"\" /></g>";
    svg #= "<g id=\"class_badge\"><image href=\""#Classes.elements[Nat8.toNat(seed[1])]#"\" /></g>";
    svg #= "<g id=\"outfit\"><image href=\""#Outfits.elements[Nat8.toNat(seed[2])]#"\" /></g>";
    svg #= "<g id=\"skin\"><image href=\""#Skins.elements[Nat8.toNat(seed[3])]#"\" /></g>";
    if (seed[4] == 1) {
      svg #= "<g id=\"scar\"><image href=\""#Scar.elements[0]#"\" /></g>";
    };
    svg #= "<g id=\"eyes\"><image href=\""#Eyes.elements[Nat8.toNat(seed[5])]#"\" /></g>";
    svg #= "<g id=\"hair\"><image href=\""#Hair.elements[Nat8.toNat(seed[6])]#"\" /></g>";
    svg #= "<g id=\"hood\"><image href=\""#Hoods.elements[Nat8.toNat(seed[7])]#"\" /></g>";
    svg #= "<g id=\"magic_ring\"><image href=\""#MagicRings.elements[Nat8.toNat(seed[8])]#"\" /></g>";
    svg #= "<g id=\"cape\"><image href=\""#Capes.elements[Nat8.toNat(seed[9])]#"\" /></g>";
    svg #= "<g id=\"weapon\"><image href=\""#Weapons.elements[Nat8.toNat(seed[10])]#"\" /></g>";
    if (seed[11] == 1) {
      svg #= "<g id=\"og_badge\"><image href=\""#OgBadge.elements[0]#"\" /></g>";
    };
    svg #= "</svg>";
    return svg;
  };
};