//
//  CopingTabVC.swift
//  HealthFoodMe
//
//  Created by 최영린 on 2022/07/15.
//

import UIKit

import RxSwift
import RxCocoa

protocol CopingGestureDelegate {
    func panGestureSwipe(isRight: Bool)
    func downPanGestureSwipe(panGesture: ControlEvent<UIPanGestureRecognizer>.Element)
}

class CopingTabVC: UIViewController {
    
    // MARK: - Properties
    var topScrollAnimationNotFinished: Bool = true
    private var isOverFlowTableView: Bool = false
    private let panGesture = UIPanGestureRecognizer()
    private var copingTVC = CopingTVC()
    private let disposeBag = DisposeBag()
    private var categoryNameList: [String] = []
    private var copingDataList: [CopingDataModel] = []
    private var currentIdx: CategoryIndex = 0 { didSet {
        copingTabTableView.reloadData()
    }}
    weak var delegate: ScrollDeliveryDelegate?
    var panDelegate: CopingGestureDelegate?
    var restaurantId = ""
    var swipeDelegate: SwipeDismissDelegate?
    
    // MARK: - UI Components
    
    private lazy var copingTabTableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.separatorStyle = .none
        tv.backgroundColor = .white
        tv.clipsToBounds = true
        tv.isScrollEnabled = false
        tv.sectionFooterHeight = 0
        tv.allowsSelection = false
        tv.bounces = false
        if #available(iOS 15, *) {
            tv.sectionHeaderTopPadding = 0
        }
        return tv
    }()
    
    // MARK: - View Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        fetchData()
        setLayout()
        setDelegate()
        registerCell()
        addPanGesture()
        addObserver()
    }
}

// MARK: - Methods

extension CopingTabVC {
    
    private func setLayout() {
        view.addSubviews(copingTabTableView)
        
        copingTabTableView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.leading.equalToSuperview().offset(20)
            make.trailing.equalToSuperview().inset(20)
            make.bottom.equalToSuperview()
        }
    }
    
    private func registerCell() {
        CategoryTVC.register(target: copingTabTableView)
        CopingTVC.register(target: copingTabTableView)
    }
    
    private func setDelegate() {
        copingTabTableView.delegate = self
        copingTabTableView.dataSource = self
    }
    
    private func addObserver() {
        addObserverAction(.copingPanGestureEnabled) { noti in
            if let state = noti.object as? Bool {
                self.panGesture.isEnabled = state
            }
        }
        
        addObserverAction(.copingTableViewScrollTop) { _ in
            self.swipeDelegate?.swipeToDismiss()
            self.delegate?.childViewScrollDidEnd(type: .coping)
        }
    }
    
    private func fetchData() {
        getMenuPrescription()
        copingTabTableView.reloadData()
    }
    
    private func addPanGesture() {
        view.addGestureRecognizer(panGesture)
        panGesture.rx.event.asDriver { _ in .never() }
            .drive(onNext: { [weak self] sender in
                guard let self = self else { return }
                let velocity = sender.velocity(in: self.view)
                let isVertical = abs(velocity.y) > abs(velocity.x)
                switch (isVertical, velocity.x, velocity.y) {
                case (true, _, let y) where y < 0:
                    self.delegate?.scrollStarted(velocity: -10, scrollView: UIScrollView())
                    
                case (true, _, let y) where y > 0:
                    self.swipeDelegate?.swipeToDismiss()
                    self.delegate?.childViewScrollDidEnd(type: .coping)

                case (false, let x, _) where x > 0:
                    self.panDelegate?.panGestureSwipe(isRight: false)

                case (false, let x, _) where x < 0:
                    self.panDelegate?.panGestureSwipe(isRight: true)

                default: return
                }
            }).disposed(by: disposeBag)
        
    }
    
    private func calculateContentCellHeight() -> CGFloat {

        let window = UIApplication.shared.windows.first { $0.isKeyWindow }
        let statusBarManager = window?.windowScene?.statusBarManager
        let statusBarView = UIView(frame: statusBarManager?.statusBarFrame ?? CGRect.zero)
        
        let statusBarHeight = statusBarView.frame.height
        let navigationBarHeight = self.navigationController?.navigationBar.frame.height ?? 0
        
        let categoryCellHeight: CGFloat = (copingDataList.count == 1 ? 20 : 72)
        let menuCellHeight: CGFloat = 44
        
        let screenHeight = UIScreen.main.bounds.height
        let topElementsHeight = statusBarHeight + navigationBarHeight + categoryCellHeight + menuCellHeight
        
        let estimatedMaximumHeight = screenHeight - topElementsHeight - 68
        let tableViewHeight = copingTableViewHeight()
        print("HEIEHE",estimatedMaximumHeight,tableViewHeight)
        if estimatedMaximumHeight > tableViewHeight {
            return tableViewHeight
        } else {
            return estimatedMaximumHeight
        }
    }
    
    private func copingTableViewHeight() -> CGFloat {
        guard !copingDataList.isEmpty,
              copingDataList.count > currentIdx else { return 1000 }
        
        let headerHeight: CGFloat = 126
        let bottomMargin: CGFloat = 52
        
        let cellCalculator = CopingCellCalculator.shared
        var cellHeight: CGFloat {
            let recommendListHeight = cellCalculator.calculateCellHeight(tipList: copingDataList[currentIdx].recommend)
            let eatingListHeight = cellCalculator.calculateCellHeight(tipList: copingDataList[currentIdx].tip)
            return recommendListHeight + eatingListHeight
        }
        
        var tableViewHeight: CGFloat {
            let calculatedHeight: CGFloat = headerHeight * 2 + cellHeight + bottomMargin * 2
            return calculatedHeight
        }
        
        return tableViewHeight
    }
}

// MARK: - Network

extension CopingTabVC {
    func getMenuPrescription() {
        RestaurantService.shared.getMenuPrescription(restaurantId: restaurantId) { networkResult in
            print(networkResult)
            switch networkResult {
            case .success(let data):
                if let data = data as? [CopingTabEntity] {
                    self.categoryNameList = data.map { $0.category }
                    self.copingDataList   = data.map { $0.prescription }
                    self.copingTabTableView.reloadData()
                }
            default:
                break;
            }
        }
    }
}

extension CopingTabVC: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == 0 {
            return copingDataList.count == 1 ? 20 : 72
        } else {
            return calculateContentCellHeight()
        }
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0
    }
}

// MARK: TableViewDataSource

extension CopingTabVC: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: CategoryTVC.className, for: indexPath) as? CategoryTVC else { return UITableViewCell() }
            cell.setCategoryData(nameList: categoryNameList)
            cell.clickedCategoryIndex = { [weak self] idx in
                self?.currentIdx = idx
                self?.copingTabTableView.reloadData()
            }
            
            return cell
        } else {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: CopingTVC.className, for: indexPath) as? CopingTVC else { return UITableViewCell() }
            cell.selectionStyle = .none
            if categoryNameList.count > currentIdx {
                cell.setData(category: categoryNameList[currentIdx],
                             data    : copingDataList[currentIdx],
                             isOnlyCategory: copingDataList.count == 1)
            }
            
            return cell
        }
    }
}
