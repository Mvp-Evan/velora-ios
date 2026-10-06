import Foundation

#if DEBUG
enum MockData {
    static let seller = User(id: 1, nickname: "老张的车库", avatar: "https://i.pravatar.cc/150?img=12", bio: "F1 与勒芒模型收藏十年", location: "上海",
                             creditScore: 98, soldCount: 42, wonCount: 7, lotCount: 5, phoneMasked: "138****0001", createdAt: Date())

    static let lot = Lot(id: 101, sellerId: 1, title: "BBR 1:18 法拉利 SF-23 勒克莱尔 2023 摩纳哥站 限量 199 台", description: "全新未拆封，附证书与原盒。",
                         images: ["https://picsum.photos/seed/velora1/800/800", "https://picsum.photos/seed/velora2/800/800"],
                         category: "F1", brand: "BBR", scale: "1:18", series: "法拉利", condition: "全新", boxStatus: "原盒全套", location: "上海",
                         startPrice: 180000, depositAmount: 10000, bidIncrement: 5000, currentPrice: 265000, currentBidderId: 2, bidCount: 17,
                         startAt: Date().addingTimeInterval(-3600), endAt: Date().addingTimeInterval(1800), durationSeconds: 5400, antiSnipeSeconds: 120,
                         extensionCount: 1, status: .live, followCount: 56, viewCount: 1289, winnerId: nil, orderId: nil, createdAt: Date(),
                         seller: seller, currentBidder: User(id: 2, nickname: "F*****子", avatar: "https://i.pravatar.cc/150?img=5", bio: nil, location: nil, creditScore: 90, soldCount: 0, wonCount: 3, lotCount: 0, phoneMasked: nil, createdAt: nil),
                         cover: "https://picsum.photos/seed/velora1/800/800", displayPrice: 265000, minNextBid: 270000, isFollowing: true,
                         myBid: MyBidStatus(hasBid: true, leading: false, maxAmount: 260000), recentBids: [], hasReserve: true, reserveMet: true)
}
#endif
