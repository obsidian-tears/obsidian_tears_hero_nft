import Nat8 "mo:base/Nat8";
import Text "mo:base/Text";

import Accessories "./elements/pups/accessories";
import Backgrounds "./elements/pups/backgrounds";
import Dogs "./elements/pups/dogs";
import Eyes "./elements/pups/eyes";
import Heads "./elements/pups/heads";
import Lips "./elements/pups/lips";
import Moles "./elements/pups/moles";
import Mouths "./elements/pups/mouths";
import Necks "./elements/pups/necks";
import Noses "./elements/pups/noses";
import Tears "./elements/pups/tears";
// END TODO

// order of assets

module {
  public func make(seed : [Nat8], check : Nat32) : Text {
    var svg : Text = "<?xml version=\"1.0\" encoding=\"utf-8\"?><svg style=\"width: 512px;height: 512px;\" version=\"1.1\" id=\"generated\" xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" x=\"0px\" y=\"0px\" viewBox=\"0 0 512 512\" xml:space=\"preserve\">";
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
    svg #= "<g id=\"dogs\"><image href=\""#Dogs.elements[Nat8.toNat(seed[1])]#"\" /></g>";
    svg #= "<g id=\"noses\"><image href=\""#Noses.elements[Nat8.toNat(seed[2])]#"\" /></g>";
    svg #= "<g id=\"tears\"><image href=\""#Tears.elements[Nat8.toNat(seed[3])]#"\" /></g>";
    svg #= "<g id=\"moles\"><image href=\""#Moles.elements[Nat8.toNat(seed[4])]#"\" /></g>";
    svg #= "<g id=\"lips\"><image href=\""#Lips.elements[Nat8.toNat(seed[5])]#"\" /></g>";
    svg #= "<g id=\"eyes\"><image href=\""#Eyes.elements[Nat8.toNat(seed[6])]#"\" /></g>";
    svg #= "<g id=\"necks\"><image href=\""#Necks.elements[Nat8.toNat(seed[7])]#"\" /></g>";
    svg #= "<g id=\"heads\"><image href=\""#Heads.elements[Nat8.toNat(seed[8])]#"\" /></g>";
    svg #= "<g id=\"mouths\"><image href=\""#Mouths.elements[Nat8.toNat(seed[9])]#"\" /></g>";
    svg #= "<g id=\"accessories\"><image href=\""#Accessories.elements[Nat8.toNat(seed[10])]#"\" /></g>";
    svg #= "</svg>";
    return svg;
  };
};