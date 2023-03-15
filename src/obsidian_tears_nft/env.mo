module {
    public let network = "local"; // ic, staging, local, beta

    public func getGameCanisterId() : Text {
        if (network == "ic") return "gagfs-yqaaa-aaaao-aaiva-cai";
        if (network == "staging") return "bjwew-5qaaa-aaaan-qc7aa-cai";
        if (network == "beta") return "2tncs-liaaa-aaaan-qdapq-cai";

        // else "local"
        return "qvhpv-4qaaa-aaaaa-aaagq-cai";
    };

    public func getItemCanisterId() : Text {
        if (network == "ic") return "goei2-daaaa-aaaao-aaiua-cai";
        if (network == "staging") return "bavpk-lyaaa-aaaan-qc7bq-cai";
        if (network == "beta") return "7tscg-xaaaa-aaaan-qdasa-cai";

        // else local
        return "renrk-eyaaa-aaaaa-aaada-cai";
    };

    public func getAdminPrincipal() : Text {
        if (network == "ic") return "6ulqo-ikasf-xzltp-ylrhu-qt4gt-nv4rz-gd46e-nagoe-3bo7b-kbm3h-bqe"; // obsidian production principal
        if (network == "staging") return "4e6g2-eoooo-h2lec-3h725-hvmmc-fvgsd-qakd3-qsj44-6dlaw-p5ngz-mae";
        if (network == "beta") return "4e6g2-eoooo-h2lec-3h725-hvmmc-fvgsd-qakd3-qsj44-6dlaw-p5ngz-mae";

        // else "local"
        return "4e6g2-eoooo-h2lec-3h725-hvmmc-fvgsd-qakd3-qsj44-6dlaw-p5ngz-mae"; // tiago's dev principal
    };
};
