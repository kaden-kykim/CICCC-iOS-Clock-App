//
//  TimerViewModel.swift
//  Clock
//
//  Created by Kaden Kim on 2020-06-10.
//  Copyright © 2020 CICCC. All rights reserved.
//

import RxSwift
import RxCocoa

protocol TimerViewModel: class {
    // Input
    var viewWillAppear: PublishRelay<Void> { get }
    var viewDidDisappear: PublishRelay<Void> { get }
    var didTapLeftButton: PublishRelay<Void> { get }
    var didTapRightButton: PublishRelay<Void> { get }
    var setTimerSound: PublishRelay<Int?> { get }
    var valueChangedPicker: PublishRelay<(Int, Int, Int)> { get }
    var pushToSelectSoundView: PublishRelay<Void> { get }
    
    // Output
    var leftButtonStatus: Driver<Bool> { get }
    var rightButtonStatus: Driver<(UIColor, String)> { get }
    var rightButtonEnabled: Driver<(Bool)> { get }
    var dueDigitalTime: Driver<String> { get }
    var isDueDigitalTimePaused: Driver<Bool> { get }
    var remainingDigitalTime: Driver<String> { get }
    var remainingCirclePercent: Driver<Double> { get }
    var setNameFromSoundID: Driver<String> { get }
    var isShownTimerPickerView: Driver<Bool> { get }
    var updateSetTimePicker: PublishRelay<(Int, Int, Int)> { get }
}

final class TimerViewModelImpl: TimerViewModel {
    
    // MARK: - Input
    let viewWillAppear = PublishRelay<Void>()
    let viewDidDisappear = PublishRelay<Void>()
    let didTapLeftButton = PublishRelay<Void>()
    let didTapRightButton = PublishRelay<Void>()
    let setTimerSound = PublishRelay<Int?>()
    let valueChangedPicker = PublishRelay<(Int, Int, Int)>()
    var pushToSelectSoundView = PublishRelay<Void>()
    
    // MARK: - Output
    let leftButtonStatus: Driver<Bool>
    var rightButtonStatus: Driver<(UIColor, String)>
    var rightButtonEnabled: Driver<(Bool)>
    let dueDigitalTime: Driver<String>
    var isDueDigitalTimePaused: Driver<Bool>
    let remainingDigitalTime: Driver<String>
    let remainingCirclePercent: Driver<Double>
    let setNameFromSoundID: Driver<String>
    let isShownTimerPickerView: Driver<Bool>
    let updateSetTimePicker = PublishRelay<(Int, Int, Int)>()
    
    
    // MARK: - Private Properties(Reactive)
    private let coordinator: TimerCoordinator
    private let disposeBag = DisposeBag()
    private let globalScheduler = ConcurrentDispatchQueueScheduler.init(queue: DispatchQueue.global())
    private let uiScheduler = ConcurrentDispatchQueueScheduler.init(qos: .userInteractive)
    private var frameUpdateDisposable = SingleAssignmentDisposable()
    private let fps = 23.976
    
    // MARK: - Private Properties(Timer)
    private let timerStatus = BehaviorRelay<TimerStatus>(value: .stop)
    private let timerDueTime = BehaviorRelay<Date?>(value: nil)
    private var timerPauseStart = BehaviorRelay<Date?>(value: nil)
    private var timerSetTime = BehaviorRelay<TimeInterval>(value: 600)
    private let timerSoundID = BehaviorRelay<Int?>(value: nil)
    
    private let remaining = BehaviorRelay<TimeInterval>(value: 0)
    private let remainingPercent = BehaviorRelay<Double>(value: 1.0)
    
    private var timerRemaining: TimeInterval {
        get {
            guard let dueTime = timerDueTime.value else { return 0 }
            guard let pauseStart = timerPauseStart.value else { return Date().distance(to: dueTime) }
            return Date().distance(to: dueTime + pauseStart.distance(to: Date()))
        }
    }
        
    // MARK: - Initialization
    init(coordinator: TimerCoordinator, timer: TimerModel) {
        self.coordinator = coordinator
        
        leftButtonStatus = timerStatus
            .map({
                switch $0 {
                case .stop: return false
                case .start, .pause: return true
                }
            })
            .asDriver(onErrorJustReturn: false)
        
        rightButtonStatus = timerStatus
            .map({
                switch $0 {
                case .stop: return (UIColor.systemGreen, "Start")
                case .start: return (UIColor.systemRed, "Pause")
                case .pause: return (UIColor.systemGreen, "Resume")
                }
            })
            .asDriver(onErrorJustReturn: (UIColor.systemGreen, "Start"))
                
        rightButtonEnabled = timerSetTime
            .map { $0 > 0.1 }
            .asDriver(onErrorJustReturn: true)
        
        dueDigitalTime = timerDueTime
            .map ({
                guard let dueDate = $0 else { return "" }
                let timeFormatter = DateFormatter()
                timeFormatter.timeStyle = .short
                return String(timeFormatter.string(from: dueDate))
            })
            .asDriver(onErrorJustReturn: "")
        
        isDueDigitalTimePaused = timerStatus
            .map { $0 == .pause }
            .asDriver(onErrorJustReturn: false)
        
        remainingDigitalTime = remaining
            .map { $0.toTimerString() }
            .distinctUntilChanged()
            .asDriver(onErrorJustReturn: "")
        
        remainingCirclePercent = remainingPercent
            .asDriver(onErrorJustReturn: 100.0)
        
        setNameFromSoundID = timerSoundID
            .map { NotificationSound.getSoundName(index: $0) ?? "Stop Playing" }
            .asDriver(onErrorJustReturn: NotificationSound.defaultName)
        
        isShownTimerPickerView = timerStatus
            .map { return $0 == .stop }
            .asDriver(onErrorJustReturn: true)
        
        timerStatus
            .observeOn(MainScheduler.instance)
            .distinctUntilChanged()
            .subscribe(onNext: { status in
                self.frameUpdater(isStart: status == .start)
                self.saveTimer()
            })
            .disposed(by: disposeBag)

        timerDueTime
            .observeOn(globalScheduler)
            .distinctUntilChanged()
            .subscribe(onNext: { _ in self.saveTimer() })
            .disposed(by: disposeBag)

        timerPauseStart
            .observeOn(globalScheduler)
            .distinctUntilChanged()
            .subscribe(onNext: { _ in self.saveTimer() })
            .disposed(by: disposeBag)
        
        timerSetTime
            .observeOn(globalScheduler)
            .distinctUntilChanged()
            .subscribe(onNext: { _ in self.saveTimer() })
            .disposed(by: disposeBag)
        
        timerSoundID
            .observeOn(globalScheduler)
            .distinctUntilChanged()
            .subscribe(onNext: { _ in self.saveTimer() })
            .disposed(by: disposeBag)
        
        bindOnViewWillAppear()
        bindOnViewDidDisappear()
        bindOnDidTapLeftButton()
        bindOnDidTapRightButton()
        bindOnSetTimerSound()
        bindOnValueChangedPicker()
        bindOnPushToSelectSoundView()
        
        loadTimer(timer: timer)
    }
    
    // MARK: - Bindings
    private func bindOnViewWillAppear() {
        viewWillAppear
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: {
                if self.timerStatus.value == .start {
                    self.frameUpdater(isStart: true)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
                        self.updateCurrentData(oneShot: true)
                        self.updateSetTimePicker.accept(self.timeIntervalToHMS())
                    }
                }
            })
            .disposed(by: disposeBag)
    }
    
    private func bindOnViewDidDisappear() {
        viewDidDisappear
            .observeOn(MainScheduler.asyncInstance)
            .subscribe(onNext: { self.frameUpdater(isStart: false) })
            .disposed(by: disposeBag)
    }
    
    private func bindOnDidTapLeftButton() {
        didTapLeftButton
            .observeOn(MainScheduler.instance)
            .subscribeOn(MainScheduler.instance)
            .subscribe(onNext: {
                switch self.timerStatus.value {
                case .start: // To Reset
                    self.timerReset()
                case .pause: // To Reset
                    self.timerReset()
                case .stop: // Disabled: Never execute
                    assertionFailure("Shouldn't be here")
                }
            })
            .disposed(by: disposeBag)
    }
    
    private func bindOnDidTapRightButton() {
        didTapRightButton
            .observeOn(MainScheduler.instance)
            .subscribeOn(MainScheduler.instance)
            .subscribe(onNext: {
                switch self.timerStatus.value {
                case .start: // To Pause
                    self.timerPause()
                case .stop: // To Start
                    self.timerStart()
                case .pause: // To Resume
                    self.timerResume()
                }
            })
            .disposed(by: disposeBag)
    }
    
    private func bindOnSetTimerSound() {
        setTimerSound
            .observeOn(MainScheduler.instance)
            .subscribeOn(MainScheduler.instance)
            .subscribe(onNext: { self.timerSoundID.accept($0) })
            .disposed(by: disposeBag)
    }
    
    private func bindOnValueChangedPicker() {
        valueChangedPicker
            .observeOn(MainScheduler.instance)
            .subscribeOn(MainScheduler.asyncInstance)
            .subscribe(onNext: {
                self.timerSetTime.accept(Double($0) * 3600 + Double($1) * 60 + Double($2)) })
            .disposed(by: disposeBag)
    }
    
    private func bindOnPushToSelectSoundView() {
        pushToSelectSoundView
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: {
                let selectSoundTVC = SelectSoundIdTableViewController()
                selectSoundTVC.selectSoundIdDelegate = self
                selectSoundTVC.soundId = self.timerSoundID.value
                selectSoundTVC.fromWhere = .timer
                self.coordinator.pushToView(viewController: selectSoundTVC)
            })
            .disposed(by: disposeBag)
    }
    
    // MARK: - Service Methods
    private let notificationID = "ClockTimerNotification"
    
    private func timerStart() {
        timerPauseStart.accept(nil)
        timerDueTime.accept(Date().addingTimeInterval(timerSetTime.value))
        timerStatus.accept(.start)
        ClockNotification.shared.createNotification(id: notificationID, interval: timerRemaining + 0.5, title: "Timer", soundId: timerSoundID.value)
    }
    
    private func timerPause() {
        timerPauseStart.accept(Date())
        timerStatus.accept(.pause)
        ClockNotification.shared.cancelNotification(id: notificationID)
    }
    
    private func timerResume() {
        if let dueTime = timerDueTime.value, let pauseStart = timerPauseStart.value {
            timerDueTime.accept(dueTime.addingTimeInterval(pauseStart.distance(to: Date())))
            timerStatus.accept(.start)
            timerPauseStart.accept(nil)
            ClockNotification.shared.createNotification(id: notificationID, interval: timerRemaining + 0.5, title: "Timer", soundId: timerSoundID.value)
        } else {
            timerReset()
        }
    }
    
    private func timerReset() {
        timerDueTime.accept(nil)
        timerPauseStart.accept(nil)
        timerStatus.accept(.stop)
        remainingPercent.accept(1.0)
        updateCurrentData(oneShot: true)
        ClockNotification.shared.cancelNotification(id: notificationID)
    }
    
    private func timeIntervalToHMS() -> (Int, Int, Int) {
        let interval = timerSetTime.value
        return (Int(interval / 3600), Int(interval / 60), Int(interval) % 60)
    }
    
    private func loadTimer(timer: TimerModel) {
        timerDueTime.accept(timer.dueTime)
        timerPauseStart.accept(timer.pauseStart)
        timerStatus.accept(timer.status)
        timerSetTime.accept(timer.setTime)
        timerSoundID.accept(timer.soundID)
        
        updateSetTimePicker.accept(timeIntervalToHMS())
        
        if timerRemaining <= 0.0 {
            timerReset()
        } else if timerStatus.value == .pause, let pauseStart = timerPauseStart.value, let dueTime = timerDueTime.value {
            let current = Date()
            timerDueTime.accept(dueTime + pauseStart.distance(to: current))
            timerPauseStart.accept(current)
        }
    }
    
    private func saveTimer() {
        DispatchQueue.global().async {
            self.coordinator.saveTimer(timer:
                TimerModel(dueTime: self.timerDueTime.value,
                           pauseStart: self.timerPauseStart.value,
                           status: self.timerStatus.value,
                           setTime: self.timerSetTime.value,
                           soundID: self.timerSoundID.value))
        }
    }
    
    private func frameUpdater(isStart: Bool) {
        frameUpdateDisposable.dispose()
        frameUpdateDisposable = SingleAssignmentDisposable()
        if isStart {
            let interval = Int(1000 / fps)
            let frameUpdater = Observable<Int>
                .interval(RxTimeInterval.milliseconds(interval), scheduler: uiScheduler)
                .map({ _ in self.updateCurrentData() })
                .replayAll()
            frameUpdateDisposable.setDisposable(frameUpdater.connect())
        }
    }
    
    private func updateCurrentData(oneShot: Bool = false) {
        let remain = self.timerRemaining
        if oneShot || remain > -0.5 {
            self.remaining.accept(remain)
            self.remainingPercent.accept(remain / (timerSetTime.value))
        } else {
            timerReset()
        }
    }
    
}

extension TimerViewModelImpl: SelectSoundIdDelegate {
    func getSoundId(soundId: Int) {
        timerSoundID.accept(soundId)
    }
}
