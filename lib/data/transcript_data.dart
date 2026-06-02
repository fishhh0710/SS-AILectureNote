class TranscriptSection {
  final String title;
  final String content;

  const TranscriptSection({required this.title, required this.content});
}

class TranscriptPage {
  final int pageNumber;
  final List<TranscriptSection> sections;

  const TranscriptPage({required this.pageNumber, required this.sections});
}

final List<TranscriptPage> chapter4_1TranscriptData = [
  const TranscriptPage(
    pageNumber: 1,
    sections: [
      TranscriptSection(
        title: "Chapter 4: The Processor",
        content: "這頁在講整章的主題。\n\n👉 重點：\nCPU 怎麼執行指令（datapath + control）",
      ),
    ],
  ),
  const TranscriptPage(
    pageNumber: 2,
    sections: [
      TranscriptSection(
        title: "Outline",
        content:
            "這頁在講接下來會做什麼。\n\n👉 重點流程：\n先看 CPU 做什麼（instruction execution）\n再看 datapath\n最後加 control",
      ),
    ],
  ),
  const TranscriptPage(
    pageNumber: 3,
    sections: [
      TranscriptSection(
        title: "Introduction",
        content:
            "這頁在講 CPU 效能怎麼來。\n\n👉 跟硬體的關係：\ndatapath 會影響 CPI\nclock 速度取決於硬體延遲\n👉 暗示：後面設計會影響效能",
      ),
    ],
  ),
  const TranscriptPage(
    pageNumber: 4,
    sections: [
      TranscriptSection(
        title: "Instruction Execution",
        content:
            "這頁在講「一條指令實際會做哪些動作」。\n\n👉 datapath 角度：\nPC → instruction memory（取指令）\nregister file（讀資料）\nALU（運算）\nmemory（必要時）\n寫回 register\n👉 重點：\n之後所有 datapath 都是在實現這幾步",
      ),
    ],
  ),
  const TranscriptPage(
    pageNumber: 5,
    sections: [
      TranscriptSection(
        title: "High-level View of a RISC-V Implementation",
        content:
            "這頁在講 RISC-V 處理器的 datapath 雛形。\n\n👉 datapath 目前包含：PC、Instruction Memory、Registers、ALU、Data Memory。",
      ),
    ],
  ),
  const TranscriptPage(
    pageNumber: 18,
    sections: [
      TranscriptSection(
        title: "回顧 Datapath 元件",
        content:
            "我想上次我們應該是談到投影片第18頁了，基本上我們把一些不同的指令，R-format 的指令需要的哪些 Datapath 的 Component，還有 Load/Store 需要的 Datapath Component，還有 Branch 的指令需要的 Datapath Component 跟各位介紹可以嗎？",
      ),
    ],
  ),
  const TranscriptPage(
    pageNumber: 19,
    sections: [
      TranscriptSection(
        title: "整合 Datapath",
        content:
            "好，那我們現在把這些 Component 再把它合在一起了，那基本上透過這些 Datapath 還有透過 Control 的電路，我們希望每一個指令都可以在一個 Clock cycle 把它完成。好，那因為每個 Datapath 裡面的 Component 或 element 在一個時間只能做一件事情，所以我們需要把這個 Data 的 memory 跟 Instruction 的 memory 把它分開，好嗎？那事實上我上次有提到就是，事實上你的 Instruction memory 跟 Data memory 其實不是，它不是你的主記憶體，它事實上是 Cache，我們會有所謂的 Instruction cache 跟 Data 的 cache，那這是兩個不同的 cache。",
      ),
    ],
  ),
  const TranscriptPage(
    pageNumber: 20,
    sections: [
      TranscriptSection(
        title: "R-Type/Load/Store Datapath",
        content:
            "我們在第五章再跟各位介紹 Cache 跟主記憶體之間的一些關聯性。另外就是我們需要透過用 Multiplexer，當你的資料來源有多個資料來源的話，那你怎麼從那些資料來源裡頭去選？所以你的電路裡面還是需要用到一些 Multiplexer。好，那我們現在把這些 Component 把它 Connect 在一起，那這裡的話主要是針對 R-type 的指令跟 Load/Store 的指令看到的 Datapath。當然這邊的 Datapath 沒有把那個 Instruction memory 放進來，那主要是 Focus 在這個 Register file 跟這個你的這個 Data memory。",
      ),
    ],
  ),
  const TranscriptPage(
    pageNumber: 21,
    sections: [
      TranscriptSection(
        title: "控制訊號的引入",
        content:
            "另外有一些控制訊號，這個我們之前在上一節課有大概跟各位介紹過，那我們很快再看一下。所以如果你要碰到這種 R-type 的指令或 Load/Store 的指令，一般來講，我想那個 Instruction Memory 那一塊不管什麼指令都會用到，你需要透過 PC 到 Instruction Memory 裡面把你 32-bit 的資料拿出來。拿出來以後，如果碰到 R-type 或 Load/Store 的指令，你需要到 Register 裡頭去把 RS1 或者是 RS2 的資料讀出來，基本上你都會讀出來。\n\n譬如說這個 Load 的指令它基本上應該不會有 RS2，因為 RS2 如果出現的話，它的欄位應該在，在你的指令的 bit 24 到 bit 20 這五個 bit 的欄位，... 將來你的這個 MemWrite 會被設成 0 了。碰到 LD 的指令，LD 的指令不會去更新你的記憶體（你的 Data memory），所以你的 MemWrite 被設成 0。所以不用擔心 RS2 的干擾。\n\n那另外你的 ALU 的話，它的第二個 input 來源有可能是從 RS2 的這個 data 過來，也有可能是要從這個 Immediate Generation Unit 所產生的，經過 Sign Extension 之後的 64 個 Bit 的 Constant 過來。如果是 R-format 你會拿到這個 RS2 的結果；如果你是 Load/Store 的話，你就會拿到這 64 個 Bit 的常數。那這邊會有一個控制訊號 ALUSrc，會控制說到底要拿 RS2 的 data 過來；還是拿 64 個 bit 的常數過來。\n\n那另外這個 ALU 要做什麼運算？需要透過一個 4 個 bit 的 ALU operation 來決定。那另外你的 Data memory 的話它有兩個控制訊號：一個是 MemRead (Memory Read)，一個是 MemWrite。\n\n那這裡的 MemtoReg 這個控制訊號就在控制說，你到底是什麼樣的資料要寫回到 RD 裡頭？那一個來源是，如果你碰到 LD 的指令的話，你要從記憶體讀 Data 出來把那個資料寫回到 RD 裡頭。所以這個 MemtoReg 應該要被設成 1，這樣才有辦法把你從 Data Memory 讀出來的 Data 寫回去。那如果你是一個 R-type 的指令的話，那這個 MemtoReg 就要設成 0，這時候你才會拿這個 ALU 算出來的結果寫回到你的 RD 裡頭。\n\n好，那如果你把這個控制訊號把它加回去，然後再把這個 Instruction Memory 把它加回去，再把這個 PC 加回去，然後再把這兩個 Adder 把它加回去的話，大概完整的 Datapath 還有控制訊號的電路大概是長成這個樣子。",
      ),
    ],
  ),
  const TranscriptPage(
    pageNumber: 22,
    sections: [
      TranscriptSection(
        title: "Control Signals 的效果",
        content:
            "所以你現在看到的這張圖上面的這些藍色，這些藍色的訊號都是控制訊號，比如說我們有 RegWrite，有這 ALUSrc、有 ALU operation 4 個 bit、有 MemWrite、有 MemRead、然後有 MemtoReg、還有這個 PCSrc，這些都是控制訊號。那我整理在這個表上面。那這裡我是從課本的 table 把它 Copy 下來。\n\n那這裡的 deasserted 就是 disable 的意思，就是我們當成是邏輯的 0 來看。那如果 Enable 也好，或 Assert 的話，都是把它的值設成邏輯的 1。有詳細說明每個控制訊號它被設成 0 或被設成 1 到底會產生什麼樣的效果。那譬如 RegWrite 如果設成 0 的話，那它對 Register 不會產生任何的效果；那如果被設成 1 的話，那麼在 Write Register 的那個 register（就是 rd）它就會被寫 Write Data 的 input 被寫進去。",
      ),
    ],
  ),
  const TranscriptPage(
    pageNumber: 23,
    sections: [
      TranscriptSection(
        title: "回顧 Instruction Formats",
        content:
            "好，那我們總共有談 R-format 的指令有四個：有 add、有 sub，還有 and 跟 or。那另外有 ld 的指令、有 sd 的指令，那另外還有一個 beq 的指令那分別屬於這四種...這四種 type。這三十二個 bit 分別會拆成什麼樣的欄位，你可以再回來參考 23 頁這邊。",
      ),
    ],
  ),
  const TranscriptPage(
    pageNumber: 24,
    sections: [
      TranscriptSection(
        title: "Datapath 與 ALU Control 控制",
        content:
            "21頁跟24頁的圖差別在哪裡？這一頁的圖主要是這個ALU的控制訊號，它需要4個bit（那個ALU operation），那4個bit的控制訊號基本上是由這個所謂的ALU control這個電路來產生。那這個 ALU control 它本身會產生 ALU operation 的四個 bit，來控制這個 ALU 要做什麼樣的運算。\n\n那它的 input 有兩個來源，其中有一個來自 instruction 的 bit 30 還有 bit 14 到 bit 12。那 bit 30 有可能是 funct7 的其中一個 bit，也有可能是你的常數的部分。bit 14 到 12 則是 funct3 這個欄位。那另外一個 input 是 ALUOp 了，這是一個兩個 bit 的控制訊號。\n\n那這個 ALUOp 會直接由我們要設計的控制電路來產生。好，那我們現在就來看看這個 control 的電路應該要怎麼設計？... 另外，你會從指令裡面把 bit 30 還有 funct 欄位的這 14 到 12 那 4 個 bit 拿出來，然後把它接到這個 ALU control 的 input。",
      ),
    ],
  ),
  const TranscriptPage(
    pageNumber: 25,
    sections: [
      TranscriptSection(
        title: "Controller Design 詳解",
        content:
            "好，那我們來看看這個 controller 應該怎麼設計。那這個 controller 分做兩部分。右側的 Main control 只解讀右邊 7 bit 的 opcode (即 Instr[6:0])，產生大部分元件的啟閉信號 (如 RegWrite 等)。\n\n左側有一個較小的 ALU control，它會拿 Main control 推出來的 2-bit (ALUOp) 結合指令中 Func7 / Func3 總共 4 個 bit 欄位來確定該對 ALU 下什麼具體操作指令。那這個 Main control 它會產生兩個 bit 的這個 ALUOp。那另外它當然會產生 MemtoReg 這個控制訊號、MemWrite、MemRead、然後 RegWrite、然後 ALUSrc。\n\n它其實不是直接產生 PCSrc，它是產生一個控制訊號叫 Branch 的控制訊號。那這個 Branch 會跟你的這個 ALU 的 Zero output 經過一個 AND gate 以後，才會產生所謂的 PCSrc 這個控制訊號。",
      ),
    ],
  ),
  const TranscriptPage(
    pageNumber: 26,
    sections: [
      TranscriptSection(
        title: "Datapath 加上 Control",
        content:
            "這樣有沒有問題？好，那下面我們來看看這個 ALU control。在看之前，這個 26 頁應該是要秀出這個比較完整的這個 Single-cycle processor，基本上把 Datapath 還有把 Control 的電路把它放上去。\n\n所以我們剛講過會有個 ALU control 在這裡。那這裡的 Control 就是我剛上一頁的所謂的 Main control。它會產生 RegWrite、會產生 ALUSrc、會產生 MemWrite、會產生 ALUOp（這個 ALUOp 是兩個 bit）。那另外產生 MemtoReg、會產生 MemRead。另外它會產生一個 Branch 的控制訊號。",
      ),
    ],
  ),
  const TranscriptPage(
    pageNumber: 27,
    sections: [
      TranscriptSection(
        title: "ALU Control 初步規則",
        content:
            "基本上這個 ALU control 它要產生的是這個 ALU operation 這四個 bit 的結果來控制你的 ALU。那如果今天碰到 load 的指令或碰到 store 的指令的話，你希望這 ALU 做加法的運算。我會把我的 ALUOp 把它設成 00（就是我的 Main control 會產生 00 來給這個 ALUOp 的訊號）。\n\n那如果今天碰到是 beq 的指令，ALU 應該做 rs1 減 rs2 的動作。這個時候我會把我的 ALUOp 把它設成 01。\n\n這個 ALUOp 這兩個 bit 的訊號怎麼設，這是我這邊我自己規定的。那如果碰到 R-type 的指令的話，我希望它被設成 10。如果今天碰到的是 R-type 的指令，R-type 的指令我們總共有四個指令：add、sub、and 跟 or。如果是 and 那我需要 ALU 做 and；如果是 add，我需要 ALU 做 add。所以這個時候我會先把我的 ALUOp 設成 10。",
      ),
    ],
  ),
  const TranscriptPage(
    pageNumber: 28,
    sections: [
      TranscriptSection(
        title: "ALU Control 的 True Table 設計",
        content:
            "你可以看看這四種格式的指令，譬如我現在有 R-type 的指令（有 add、sub、and、or 這四種），這四種指令如果你去看它們的 opcode，最右邊的 7 個 bit 從 bit 6 到 bit 0 一定是這指令的 opcode，皆為 0110011。那如果碰到 ld 則是 0000011，sd 是 0100011，beq 是 1100011。\n\n這七個指令只有三種情況：LD 跟 SD (ALUOp設 00)，Branch 指令 (設 01)，R-type (設 10)。至於 ALU 具體要做什麼樣的運算，那就看那個 R-type 是哪一個指令：是 add 就做加、是 sub 就做減、是 and 就做 and、是 or 就做 or。\n\n如果是 LD、SD 或 BEQ，因為 ALUOp 會是 00 或者是 01，這時候我就直接把 ALU operation 的 4 個 bit 設成 0010 或是 0110 去執行加減的指令。所以我真的不需要去在乎你的 funct3 或 funct7 那四個 bit 到底是 0 還是 1。I don't care！這就是 input 的 don't care。\n\n那我們來看如果是 R-format（ALUOp = 10）時，那 4 個 bit 究竟長什麼樣子？它們的 funct3，add 跟 sub 都是 000，and 是 111，or 是 110。所以如果是 111，我就知道要做 AND 動作，輸出 0000；若是 110，輸出 0001 (OR)。如果 funct3 是 000，我再看 bit 30 是 0 還是 1。如果是 0 我知道你是加 (0010)；若是 1 我就知道你要做減 (0110)。\n\n這就是整理成表的 ALU control truth table。這總共有六個 input bit：ALUOp (2 bit) + bit 30 + funct3 (3 bit)，然後產生對應的 4 個 output bit (ALU operation)。",
      ),
    ],
  ),
  const TranscriptPage(
    pageNumber: 29,
    sections: [
      TranscriptSection(
        title: "最終 Datapath 與 Main Control Unit",
        content:
            "好，所以我們的電路應該現在就長成像 29 頁這樣子。有一個 Control 的電路，然後這個 control 另外還有一個 ALU control。大概是這兩個電路來產生這些控制訊號（這個 control 就是我講的 main control）。",
      ),
    ],
  ),
  const TranscriptPage(
    pageNumber: 30,
    sections: [
      TranscriptSection(
        title: "設置 Control Signals",
        content:
            "你看這個 Truth table，我要告訴 Main control... 我們把那些 output 再很快的跑一次：ALUOp1, ALUOp0, ALUSrc, MemtoReg, RegWrite, MemRead, MemWrite, Branch。\n\n碰到 R-format 的指令，這六個訊號要怎麼怎麼設置？ALUSrc 要設成 0 來選取 Read data 2 而不是 imm gen；MemtoReg 設成 0 選取 ALU output；RegWrite 設成 1 因為需要將結果寫回 RD；MemRead 跟 MemWrite 都不牽涉，所以設 0，Branch 設 0。\n\n那很快地看 ld 指令，ALUSrc 就應該設成 1 (選立即數)；MemtoReg 設成 1 (選擇來自 data memory 的結果)；RegWrite 設 1，且要讀 memory 所以 MemRead 設 1，MemWrite 跟 Branch 設 0。\n\nsd 指令則把 ALUSrc 設 1，MemWrite 設 1，MemRead、RegWrite 設 0，Branch 設 0。這個 MemtoReg 被標記為 X (Don't care)。最後 beq 也是類似情況，RegWrite 和 MemRD、MemWR 都為 0，ALUSrc 設 0 比較 RS1、RS2，然後 Branch 設 1。這就是 Main Control Truth table 給出這個硬體該產生了哪一些結果。",
      ),
    ],
  ),
  const TranscriptPage(
    pageNumber: 32,
    sections: [
      TranscriptSection(
        title: "R-Type Instruction 的執行流程",
        content:
            "好，下面我們來看一下這個 Single-cycle processor 它的一些不同型態指令的執行過程。看看這 Add (R-type) 指令的過程：從 PC 把指令 Fetch 出來，PC Increment +4，然後取出 X2、X3 到 ALU 去運算，最後寫回 Destination Register X1。在這投影片 33 頁我們把相關路徑用較深的顏色強調顯示，也就是這些加深的粗線表示當下這個時鐘週期真正的 Data flow！",
      ),
    ],
  ),
  const TranscriptPage(
    pageNumber: 34,
    sections: [
      TranscriptSection(
        title: "Load/Store Instruction 的執行流程",
        content:
            "那如果今天是執行 ld 的指令呢？這 35 頁的系統圖面上描繪 Load 指令，資料經過 Sign-extend 再由 ALU 計算位置，並從 Data memory 把這筆資料取回交給暫存器 X1。你可以明顯對比出 MUX 的不同路徑！",
      ),
    ],
  ),
  const TranscriptPage(
    pageNumber: 36,
    sections: [
      TranscriptSection(
        title: "Branch Instruction 的執行流程",
        content:
            "如果碰到 beq 這張投影片 37 頁，Data 根本沒進去 register write 或者 data memory，而是跑到上面去算 Target address 和判斷 Zero 來選擇 PC 源頭。這就描繪了 Branch 指令的資料跑的軌跡。",
      ),
    ],
  ),
  const TranscriptPage(
    pageNumber: 38,
    sections: [
      TranscriptSection(
        title: "Performance Issues",
        content:
            "最後我們來看一下 Single-cycle process 有什麼問題？這個 clock period 應該是由哪一個指令花的時間最長來決定的？那理論上應該是 LD 這個指令花的時間最長！因為 LD 他要 Instruction fetch, register read, ALU calculate, Data Memory read，還要 Register write 回去，這些動作都需要花時間。\n\n可是你的你要設計這個 process 是一個 synchronized 的電路，只有一個統一的 Clock Period，所以你的 Clock period 必須能滿足『最後、最慢完成』那個指令！這違背了讓 Common case 跑快一點的設計精神。為了解決這個問題，預告下次會切入 Pipelining。這整個 Single cycle 只是先給你個概念這 7 個指令跟訊號要怎麼跑而已。好，那我想這部分的內容我們就先介紹到這裡。",
      ),
    ],
  ),
];
