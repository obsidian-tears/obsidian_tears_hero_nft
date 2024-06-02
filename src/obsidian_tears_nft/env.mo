import Array "mo:base/Array";
import Principal "mo:base/Principal";
import Text "mo:base/Text";

module {
    public let network = "local"; // ic, staging, local, beta

    public func getAdminPrincipals() : [Text] {
        if (network == "ic") return ["6ulqo-ikasf-xzltp-ylrhu-qt4gt-nv4rz-gd46e-nagoe-3bo7b-kbm3h-bqe"]; // obsidian production principal
        if (network == "staging") return ["4e6g2-eoooo-h2lec-3h725-hvmmc-fvgsd-qakd3-qsj44-6dlaw-p5ngz-mae"];
        if (network == "beta") return ["4e6g2-eoooo-h2lec-3h725-hvmmc-fvgsd-qakd3-qsj44-6dlaw-p5ngz-mae"];

        // else "local"
        return [
            "4e6g2-eoooo-h2lec-3h725-hvmmc-fvgsd-qakd3-qsj44-6dlaw-p5ngz-mae",
            "heq22-7v76v-gwzlq-hl5da-czgby-ghdql-sas4k-ii2tr-voaep-amcsi-tqe",
        ]; // tiago and gastao's dev principals
    };

    public func isAdmin(caller : Principal) : Bool {
        let _minters : [Text] = getAdminPrincipals();
        let callerText = Principal.toText(caller);

        return Array.indexOf<Text>(callerText, _minters, Text.equal) != null;
    };
};
