import 'package:flutter/material.dart';

class AppConstants {
  // 圖片資源路徑 (佔位符)
  static const String luffyAwake = 'assets/images/luffy_awake.png';
  static const String luffySleeping = 'assets/images/luffy_sleeping.png';
  static const String luffyHappy = 'assets/images/luffy_happy.png';
  static const String luffyInterrupted = 'assets/images/luffy_interrupted.png';

  // 顏色
  static const Color backgroundColor = Color(0xFFFDF6E3); // 米黃色低飽和度暖色
  static const Color primaryTextColor = Color(0xFF5C4B51);
  static const Color primaryButtonColor = Color(0xFFE2A76F); // 溫暖的橘色調
  static const Color cancelButtonColor = Color(0xFFD6C5B3);

  // 統計頁面用色
  static const Color chartBarColor = Color(0xFFE2A76F); // 柱狀圖主色（橘色，與主按鈕色一致）
  static const Color chartBarInactive = Color(0xFFE8D5C4); // 柱狀圖非今日色
  static const Color streakFireColor = Color(0xFFFF6B35); // 連續天數火焰色
  static const Color cardBackground = Color(0xFFFFFFFF); // 統計卡片背景

  // 睡前小故事列表 (加長版，依序循環播放)
  static const List<String> bedtimeStories = [
    "【路飛與奇幻森林的蝴蝶】\n今天下午，陽光透過窗台灑在地板上，路飛正追著一隻閃閃發光的藍色蝴蝶。不知不覺中，客廳的角落竟出現了一扇發著微光的木門。路飛好奇地用鼻子頂開了門，發現門後是一片一望無際的奇幻森林。這裡的草地軟得像棉花糖，空氣中瀰漫著烤肉骨頭的香氣。路飛興奮地在草地上奔跑，沿途遇到了戴著圓頂禮帽的松鼠，還有會唱歌的蘑菇。當牠跑到森林深處時，發現了一個長滿發光花朵的秘密花園。路飛在花園中央找到了一塊最柔軟的草地，心滿意足地趴了下來。伴隨著微風與花香，牠的眼睛漸漸閉上，進入了甜美的夢鄉。就在剛才的這段時間裡，你也完成了一次超棒的專注，和路飛一樣，值得好好休息一下了！",
    "【勇敢的柴犬騎士】\n在路飛的夢境裡，牠變成了一位披著紅色披風的勇敢騎士。這座名為「肉泥小鎮」的地方，最近受到了一隻巨大橘貓的威脅。橘貓總是喜歡在半夜跑到鎮上，把小動物們嚇得東奔西跑。路飛騎士挺身而出，牠帶著最喜歡的啾啾玩具骨頭，來到了橘貓的巢穴。面對巨大的橘貓，路飛沒有退縮，而是勇敢地叫了一聲：「汪！」。沒想到，橘貓其實只是想找人玩耍。於是，路飛把啾啾骨頭送給了橘貓，兩隻毛茸茸的動物立刻成為了最好的朋友。小鎮的居民為了感謝路飛，舉辦了一場盛大的派對，並頒發給牠「無限量肉泥獎章」。現在，這位英雄正在夢裡吧唧著嘴，享受著無盡的美食。你的專注也像騎士一樣堅定，做得非常好！",
    "【路飛的星空航海記】\n夜幕低垂，路飛戴上了一頂小小的水手帽，搭乘著一艘木製的小船，航行在平靜無波的星空之海。這片海洋的水是溫暖的，水面上倒映著天空中無數閃爍的繁星。路飛趴在船頭，看著偶爾躍出水面的飛魚，每隻飛魚都帶著淡淡的螢光。突然，天空中劃過一道巨大的流星雨，路飛開心地搖著尾巴，對著流星許下了一個願望：「希望能有吃不完的蘋果切片和永遠不會壞掉的網球」。流星彷彿聽懂了牠的話，化作一陣溫柔的星塵灑落在小船上。路飛感覺全身暖洋洋的，伴隨著海浪輕輕搖晃的節奏，牠把下巴靠在爪子上，安心地睡著了。這25分鐘的航程，你也航向了目標的彼岸，辛苦了！",
    "【雲端上的棉花糖樂園】\n今天路飛做了一個好甜的夢。牠發現自己輕飄飄地飛上了天空，來到了一個完全由白雲構成的樂園。這裡的雲朵不僅踩起來軟綿綿的，而且竟然是香草棉花糖的口味！路飛忍不住張開嘴巴咬了一大口雲朵，甜甜的滋味讓牠開心得在雲端上打滾。不久後，牠遇到了幾隻同樣飛到天上的「雲朵狗狗」，大家一起在天空中玩起了你追我跑的遊戲。牠們穿梭在彩虹之間，把雲朵撞成各種有趣的形狀。玩累了之後，路飛找到了一朵最厚、最蓬鬆的晚霞雲，橘紅色的光芒照在牠身上，溫暖又舒適。牠打了一個大大的哈欠，慢慢地進入了更深層的夢境。你的努力就像雲朵一樣累積，現在可以稍微放鬆一下，吃點甜食獎勵自己吧！",
    "【秋日秘境與烤番薯】\n雖然現在不是秋天，但路飛的夢裡卻充滿了金黃色的落葉。在夢中，路飛來到了一片神秘的楓樹林，地上的落葉積得像小山一樣高。這可是路飛的最愛！牠毫不猶豫地助跑，然後「撲通」一聲整隻狗鑽進了落葉堆裡，只露出一條搖來搖去的捲尾巴。就在牠玩得不亦樂乎的時候，遠處飄來了一陣難以抗拒的香氣。路飛順著香味找去，發現了一隻正在烤地瓜的狸貓爺爺。狸貓爺爺笑呵呵地遞給路飛一顆剛烤好、熱騰騰且流著蜜汁的黃金地瓜。路飛小心翼翼地咬了一口，甜美的滋味瞬間在嘴裡化開。吃飽喝足後，路飛靠在溫暖的火爐旁，聽著柴火劈啪作響的聲音，安穩地睡著了。這段時光充滿了收穫，正如你剛完成的專注一樣，充實而美好。"
  ];

  // 自定義寵物上限（不含預設路飛），加上路飛共 3 個
  static const int maxCustomPets = 2;

  // 預設倒數時間 (秒) - 25 分鐘
  static const int defaultTimerSeconds = 25 * 60;

  // App 版本號
  static const String appVersion = '1.1.0';
}
