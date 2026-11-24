//  ChatSwapStep3SpikeTests.swift
//  OneDayAppTests · §374.3 定因 spike（定因存档：组树形状成本关系把守）
//
//  纯 UIKit 裸装配：分清 compositional 布局
//  pass 成本由「组树形状」还是「逐 item 帧求
//  解」主导——三变体（逐行一 section／单
//  section 逐行一子组／单 section 单组多
//  item）×300/1200 行，量全量布局 pass 与单
//  item reconfigure apply 两口。结论回填
//  §374.3；三变体成本关系回潮即红

import UIKit
import XCTest

@MainActor
final class ChatSwapStep3SpikeTests: XCTestCase {

    private var window: UIWindow?

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    private enum Shape: String {
        case sections
        case subgroups
        case flatItems
    }

    private func measureMinMicroseconds(
        warmup: Int = 2, reps: Int = 5,
        _ body: () -> Void
    ) -> Double {
        for _ in 0..<warmup { body() }
        var best = Double.greatestFiniteMagnitude
        for _ in 0..<reps {
            let start = CFAbsoluteTimeGetCurrent()
            body()
            best = min(
                best,
                (CFAbsoluteTimeGetCurrent() - start)
                    * 1_000_000
            )
        }
        return best
    }

    func testLayoutShapeCostSpike() {
        var lines: [String] = []
        for shape in [Shape.sections, .subgroups, .flatItems] {
            for count in [300, 1200] {
                let result = runShape(shape, count: count)
                lines.append(
                    "\(shape.rawValue)-\(count): pass=\(Int(result.pass))µs apply=\(Int(result.apply))µs"
                )
            }
        }
        print("[swap3-spike] " + lines.joined(separator: " "))
    }

    private func runShape(
        _ shape: Shape, count: Int
    ) -> (pass: Double, apply: Double) {
        let rowHeight: CGFloat = 80
        let spacing: CGFloat = 24
        let layout = UICollectionViewCompositionalLayout {
            (sectionIndex, _) -> NSCollectionLayoutSection? in
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(rowHeight)
            )
            let item = NSCollectionLayoutItem(
                layoutSize: itemSize
            )
            switch shape {
            case .sections:
                let group = NSCollectionLayoutGroup
                    .vertical(
                        layoutSize: NSCollectionLayoutSize(
                            widthDimension:
                                .fractionalWidth(1),
                            heightDimension:
                                .absolute(rowHeight)
                        ),
                        subitems: [item]
                    )
                let section = NSCollectionLayoutSection(
                    group: group
                )
                section.contentInsets = NSDirectionalEdgeInsets(
                    top: 0, leading: 20, bottom: 0,
                    trailing: 20
                )
                return section
            case .subgroups:
                guard sectionIndex == 0 else { return nil }
                let sub = NSCollectionLayoutGroup.vertical(
                    layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(1),
                        heightDimension:
                            .absolute(rowHeight)
                    ),
                    subitems: [item]
                )
                let total = rowHeight * CGFloat(count)
                    + spacing * CGFloat(count - 1)
                let root = NSCollectionLayoutGroup.vertical(
                    layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(1),
                        heightDimension: .absolute(total)
                    ),
                    subitems: Array(
                        repeating: sub, count: count
                    )
                )
                root.interItemSpacing = .fixed(spacing)
                let section = NSCollectionLayoutSection(
                    group: root
                )
                section.contentInsets = NSDirectionalEdgeInsets(
                    top: 16, leading: 20, bottom: 8,
                    trailing: 20
                )
                return section
            case .flatItems:
                guard sectionIndex == 0 else { return nil }
                let total = rowHeight * CGFloat(count)
                    + spacing * CGFloat(count - 1)
                let root = NSCollectionLayoutGroup.vertical(
                    layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(1),
                        heightDimension: .absolute(total)
                    ),
                    subitems: Array(
                        repeating: item, count: count
                    )
                )
                root.interItemSpacing = .fixed(spacing)
                let section = NSCollectionLayoutSection(
                    group: root
                )
                section.contentInsets = NSDirectionalEdgeInsets(
                    top: 16, leading: 20, bottom: 8,
                    trailing: 20
                )
                return section
            }
        }
        let cv = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844),
            collectionViewLayout: layout
        )
        let win = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844)
        )
        let rootVC = UIViewController()
        win.rootViewController = rootVC
        win.makeKeyAndVisible()
        rootVC.view.addSubview(cv)
        cv.frame = rootVC.view.bounds
        window = win

        typealias DS = UICollectionViewDiffableDataSource<
            String, String
        >
        let registration = UICollectionView.CellRegistration<
            UICollectionViewCell, String
        > { _, _, _ in }
        let dataSource = DS(collectionView: cv) {
            cv, indexPath, id in
            cv.dequeueConfiguredReusableCell(
                using: registration,
                for: indexPath, item: id
            )
        }
        func snapshot() -> NSDiffableDataSourceSnapshot<
            String, String
        > {
            var snap = NSDiffableDataSourceSnapshot<
                String, String
            >()
            switch shape {
            case .sections:
                for i in 0..<count {
                    snap.appendSections(["s\(i)"])
                    snap.appendItems(
                        ["r\(i)"], toSection: "s\(i)"
                    )
                }
            case .subgroups, .flatItems:
                snap.appendSections(["main"])
                snap.appendItems(
                    (0..<count).map { "r\($0)" },
                    toSection: "main"
                )
            }
            return snap
        }
        dataSource.apply(snapshot(), animatingDifferences: false)
        cv.layoutIfNeeded()
        let pass = measureMinMicroseconds {
            cv.collectionViewLayout.invalidateLayout()
            cv.layoutIfNeeded()
        }
        let midID = "r\(count / 2)"
        let apply = measureMinMicroseconds {
            var snap = dataSource.snapshot()
            snap.reconfigureItems([midID])
            dataSource.apply(
                snap, animatingDifferences: false
            )
        }
        return (pass, apply)
    }
}
