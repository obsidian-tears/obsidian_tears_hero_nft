import Nat8 "mo:base/Nat8";
import Text "mo:base/Text";

import Backgrounds "elements/backgrounds";
import Capes "elements/capes";
import Classes "elements/classes";
import Eyes "elements/eyes";
import Hair "elements/hair";
import Hoods "elements/hoods";
import MagicRings "elements/magic_rings";
import OgBadge "elements/og_badge";
import Outfits "elements/outfits";
import Scar "elements/scar";
import Skins "elements/skins";
import Weapons "elements/weapons";
// END TODO

// order of assets

module {
  public func make(seed : [Nat8], height : Text, width : Text, battle: Bool) : Text {
    var svg : Text = "<?xml version=\"1.0\" encoding=\"utf-8\"?><svg style=\"height:" #height # "px;width:" #width # "px;\" version=\"1.1\" id=\"generated\" xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" x=\"0px\" y=\"0px\" viewBox=\"0 0 " #width # " " #height # "\" xml:space=\"preserve\">";
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
    if (battle == false) {
      svg #= "<g id=\"backgrounds\"><image style=\"height:" #height # "px;width:" #width # "px;\" href=\"" #Backgrounds.elements[Nat8.toNat(seed[0])] # "\" /></g>";
      svg #= "<g id=\"class_badge\"><image style=\"height:" #height # "px;width:" #width # "px;\" href=\"" #Classes.elements[Nat8.toNat(seed[1])] # "\" /></g>";
      if (seed[11] == 1) {
        svg #= "<g id=\"og_badge\"><image style=\"height:" #height # "px;width:" #width # "px;\" href=\"" #OgBadge.elements[0] # "\" /></g>";
      };
    };
    svg #= "<g id=\"outfit\"><image style=\"height:" #height # "px;width:" #width # "px;\" href=\"" #Outfits.elements[Nat8.toNat(seed[2])] # "\" /></g>";
    svg #= "<g id=\"skin\"><image style=\"height:" #height # "px;width:" #width # "px;\" href=\"" #Skins.elements[Nat8.toNat(seed[3])] # "\" /></g>";
    if (seed[4] == 1) {
      svg #= "<g id=\"scar\"><image style=\"height:" #height # "px;width:" #width # "px;\" href=\"" #Scar.elements[0] # "\" /></g>";
    };
    svg #= "<g id=\"eyes\"><image style=\"height:" #height # "px;width:" #width # "px;\" href=\"" #Eyes.elements[Nat8.toNat(seed[5])] # "\" /></g>";
    svg #= "<g id=\"hair\"><image style=\"height:" #height # "px;width:" #width # "px;\" href=\"" #Hair.elements[Nat8.toNat(seed[6])] # "\" /></g>";
    svg #= "<g id=\"hood\"><image style=\"height:" #height # "px;width:" #width # "px;\" href=\"" #Hoods.elements[Nat8.toNat(seed[7])] # "\" /></g>";
    svg #= "<g id=\"magic_ring\"><image style=\"height:" #height # "px;width:" #width # "px;\" href=\"" #MagicRings.elements[Nat8.toNat(seed[8])] # "\" /></g>";
    svg #= "<g id=\"cape\"><image style=\"height:" #height # "px;width:" #width # "px;\" href=\"" #Capes.elements[Nat8.toNat(seed[9])] # "\" /></g>";
    svg #= "<g id=\"weapon\"><image style=\"height:" #height # "px;width:" #width # "px;\" href=\"" #Weapons.elements[Nat8.toNat(seed[10])] # "\" /></g>";
    svg #= "</svg>";
    return svg;
  };
};
