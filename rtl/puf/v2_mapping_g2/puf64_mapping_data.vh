// AUTO-GENERATED for mapping generation G2 (tag 0x005d). Do not edit.
// Source: constraints/puf64_g2_mapping_manifest.json + g2_train_mapping_candidate.json.
// Mapping bit convention (frozen, audited):
//   pair j = ordered_pairs[j] = (a,b), 0 <= a < b < 64.
//   response bit j = 1 if count_a < count_b, 0 if count_a > count_b.
//   count_a == count_b is a tie: CORRECTABLE, the scheduler stores a
//   deterministic 0 and lets the BCH (t=8) correct it; at most 2 ties
//   per sweep are absorbed, a 3rd tie fails closed. KCV still gates.
//   FE vector packs LSB-first: bit j -> byte j/8, bit j%8.
localparam integer PUF64_MAP_LEN_BITS   = 264;
localparam integer PUF64_MAP_LEN_BYTES  = 33;
localparam integer PUF64_MAP_PAIR_COUNT = 264;
localparam [15:0]  PUF64_MAP_TAG        = 16'h005d;
localparam [255:0] PUF64_MAP_DIGEST_SHA3_256 = 256'h5d00c4d49a90b127ff618a00c12be633648672a8267fde28fb2cdedaaef8a770;
localparam [255:0] PUF64_MAP_SELECTION_SHA256 = 256'hea877a5915e9d2855c018145468a7a89dca0482cefa44bf2bc8e14d31c8e3889;
// {a[5:0], b[5:0]} per pair, pair 0 at the most significant end.
localparam [3167:0] PUF64_MAP_PAIRS = 3168'h23dafa5fc0df328107c3847bb722794b49336365af7634de29b431fbf6a77353ac86906a1550221ae2200ab5e57e63191142fd37a3fcc370fba2d1f94b84769322568f44f3298bf177f69e6f539087e06715c8aca6e3ea2d500d18882b0977e532611953ddfac3ca3b0ed4791d2938cb65b42634d82b3bff77169b7b54213be05c167b2e8a92ea35500f1ab0885e065f325126dfd53aefc0f01eda39452db82645b28f34f42af6317bf69d39b43507e86772216c2e9aae3d50142259ab1977e008c13737d670ebbb7c0f94a81e42765b84634f22b4c7363f6af77539e6e105017e8a72dc36c3e956e52a03722696b5d919f320084c3db7a1fbe7c0d2928d364568f82532b2cff61abf57b139d05b1508be7219ee2ec369ab751502b2195e609f18c1203fd970e7ae3b46d4bc0e4a361d68f224a4efc746b36356ff76105e422bbe3a73dc16952c36a00b57766b10683097d0bb9ba23c0d77e81ccb78cb9252464cf65988efd3f4dd29e6f141ad7e39c3e786c06916a56202e214af72d735f1251b083b67d0ba9bc0cc26de39;
// Sorted canonical-sweep lookup: (full_pair_index[10:0], dest[7:0]).
localparam [2903:0] PUF64_MAP_SORTED_FULL = 2904'h014030070130420a81683609a1602c85b0c81983387b0fc208430911322945a0b5184320668d51b438c730ef1e23dc7c1052144448b1172504eca01472a4550aa9572d25b0b817b30663cc91943506b8d91c0392754eb9e73d87ccfc1f941e84109a1b43887d1622d46c8fd212564b297136a704e29c943a8951ca6d4e29e55eaf962aca596b35762f6600c0581b11628c6191b2464ac9997b3468cd35aa35f6c2d89ba375702e21c4b98738e9dd5bb8772f09e5bce7a0fa9fb3fa7fd01a05c0c83b08210c2285d10e22c538ad19638c7a90926e4f4a09492b65a4b99753426acec9e13c67d500a194468f521a4749296d35a7352eadd5fad35bab7d82b2164ad05a4b5d706e2dcfba1756eb5d8bf57ff05614c2d86715e31c678db24655cb19672d65ecd39cf3a679d0da2f4c69fd5dac35d6d0db3b736f6e7df9c178cf1ce47ce79ff41e87d5bacf5decfdbbb7f73ee9de3bcf88f17e53cef9ff51ec7da7bef83f13e37cbf9bf47eb7df;
localparam [2375:0] PUF64_MAP_SORTED_DEST = 2376'h6d8ecb67b0caf1f49c4a2ccaad31abdc2e7451175003e5f87206e182a9dc80364118ca8612b780a2020b05fe6140ad030362b361f0774a8f1807e5017035007312194883309d4afb5e86cf89d7180198e9560ac986a83224122e083c0dcad2723474fd4b9e0b2b81087d426020010b4fe5cb693022410cce4f459249ac152a1e9aef54c8e446c27914da811399a1548b75318524703a1c142863935de0f66a305a6d5da6db263213e534dc76034d64b4527cbc1d5f0095e6f680311e5f6ea0e0451388c4269067a4de23268ad8ec1469038a091182c4a4703f8fc3ce51eb7e02750b3d868962c0dd6aed659b058ab540a816494f30dc07d714116e266499c8a383cae9f8012b821cea442b545eb0278900c4451a399c4a743ad5ca9773ccd2433141d8ac453210c812;
function automatic [10:0] puf64_map_sorted_full(input integer j);
    puf64_map_sorted_full = PUF64_MAP_SORTED_FULL[2904-1 - 11*j -: 11];
endfunction
function automatic [8:0] puf64_map_sorted_dest(input integer j);
    puf64_map_sorted_dest = PUF64_MAP_SORTED_DEST[2376-1 - 9*j -: 9];
endfunction
function automatic [5:0] puf64_map_pair_a(input integer j);
    puf64_map_pair_a = PUF64_MAP_PAIRS[3168-1 - 12*j -: 6];
endfunction
function automatic [5:0] puf64_map_pair_b(input integer j);
    puf64_map_pair_b = PUF64_MAP_PAIRS[3168-1 - 12*j - 6 -: 6];
endfunction
