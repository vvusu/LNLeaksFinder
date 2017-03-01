# LNLeaksFinder

# iOS_内存泄漏
为了测试内存泄漏方便，封装了一个Framework。

相似框架
[MLeaksFinder](https://wereadteam.github.io/2016/02/22/MLeaksFinder/)
[PLeakSniffer](http://mrpeak.cn/blog/leak/)

使用的时候直接导入Framework就可以，而且只在debug下开启, 真机会报错误，请删处Framework。

###内存泄漏注意事项

1.Block里面`self`强引用

```
_headerView.followClickBlock = ^() {
  if (![self isLogin]) {
      [[MRouter sharedRouter] handleURL:[NSURL URLWithString:@"https://passport.wallstreetcn.com/login"] userInfo:nil];
      return;
  }
  [weakSelf dealFollowClick];
};
```
block 里面的self用`wself`替换

```
__weak typeof(self) wself = self;
```

2.自定义代理时强引用delegate 会造成内存泄漏；

如果父VC持有子VC，并设置子VC的delegate为self（也就是父VC），这样的结果就是子VC也间接持有了父VC，造成循环引用，在Pop子VC的时候不会调用delloc.

```
@property (nonatomic, strong) id<ProfileEditPickerViewDelegate> delegate;
```

把`strong`修饰符改为`weak` 不用`assign`

3.OC和CF转化出现的内存警告用完添加`CFRelease()`释放对象

```
CFStringRef cfString = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,(CFStringRef)picDataString,NULL,CFSTR(":/?#[]@!$&’()*+,;="),kCFStringEncodingUTF8);
NSString *baseString = [NSString stringWithString:(NSString *)cfString];
CFRelease(cfString); //不添加会泄漏
```
4.CATransition 动画`removedOnCompletion`属性

```
    CATransition *animation = [CATransition animation];
    animation.delegate = self;
    animation.duration = 0.3f;
    animation.timingFunction = UIViewAnimationCurveEaseInOut;
    animation.fillMode = kCAFillModeForwards;
    animation.type = kCATransitionPush;
    animation.subtype = kCATransitionFromLeft;
    animation.startProgress = 0.0;
    animation.endProgress = 1.0;
    animation.removedOnCompletion = NO; //有内存泄漏的风险
    [self.layer addAnimation:animation forKey:@"animation"];
    [self.textField resignFirstResponder];

```

5.NSTimer
NSTimer会造成循环引用，timer会强引用target即self，在加入runloop的操作中，又引用了timer，所以在timer被invalidate之前，self也就不会被释放。
所以我们要注意，不仅仅是把timer当作实例变量的时候会造成循环引用，只要申请了timer，加入了runloop，并且target是self，虽然不是循环引用，但是self却没有释放的时机。如下方式申请的定时器，self已经无法释放了。

```
NSTimer *timer = [NSTimer timerWithTimeInterval:5 target:self selector:@selector(commentAnimation) userInfo:nil repeats:YES];
[[NSRunLoop currentRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
```
解决这种问题有几个实现方式，大家可以根据具体场景去选择：

增加startTimer和stopTimer方法，在合适的时机去调用，比如可以在viewDidDisappear时stopTimer，或者由这个类的调用者去设置。
每次任务结束时使用dispatch_after方法做延时操作。注意使用weakself，否则也会强引用self。

```
- (void)startAnimation {
	__weak typeof(self) wself = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf commentAnimation];
    });
}
```
使用GCD的定时器，同样注意使用weakself。

```
__weak typeof(self) wself = self;
timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC, 1 * NSEC_PER_SEC);
dispatch_source_set_event_handler(timer, ^{
    [weakSelf commentAnimation];
});
dispatch_resume(timer);
```

6.NSNotification
使用block的方式增加notification，引用了self，在删除notification之前，self不会被释放，与timer的场景类似，其实这段代码已经声明了weakself，但是调用_eventManger方法还是引起了循环引用。
也就是说，即使我们没有调用self方法，_xxx也会造成循环引用。

```
[[NSNotificationCenter defaultCenter] addObserverForName:kUserSubscribeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
    if (note) {
        Model *model=(Model *)note.object;
        if ([model.subId integerValue] == [weakSelf.subId integerValue]) {
            [_eventManger playerSubsciption:NO];
        }
    }
}
```

7.有一些图片很大用`[UIImage imageNamed:@""]`加载的话回常驻内存，建议大的图片加载从本地文件加载`[UIImage imageWithContentsOfFile:@""]`

8.performSelector延时调用导致的内存泄露

```
[self performSelector:@selector(method1:) withObject:self.tableLayer afterDelay:3];
```
有时切换场景时延时函数已经被调用但还没有执行，这时tableLayer的引用计数没有减少到0，也就导致了切换场景dealloc方法没有被调用，出现了内存泄露。
所以解决办法就是取消那些还没有来得及执行的延时函数：

```
[NSObject cancelPreviousPerformRequestsWithTarget:self]
```


