class BillingService {
  /// 檢查用戶是否已解鎖「上傳自定義寵物」的權限
  /// 前期預留接口，固定回傳 true
  Future<bool> canUnlockCustomPet() async {
    // TODO: 串接 In-App Purchase (IAP) 判斷邏輯
    await Future.delayed(const Duration(milliseconds: 500)); // 模擬網路請求延遲
    return true;
  }

  /// 觸發購買解鎖自定義寵物流程
  Future<bool> purchaseCustomPetUnlock() async {
    // TODO: 串接 In-App Purchase (IAP) 購買邏輯
    await Future.delayed(const Duration(seconds: 1)); // 模擬購買過程
    return true; // 購買成功
  }
}
