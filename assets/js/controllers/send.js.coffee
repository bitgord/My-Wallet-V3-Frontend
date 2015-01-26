@SendCtrl = ($scope, $log, Wallet, $modalInstance, ngAudio, $timeout, $state, $stateParams, $translate, paymentRequest) ->
  $scope.legacyAddresses = Wallet.legacyAddresses
  $scope.accounts = Wallet.accounts
  $scope.addressBook = Wallet.addressBook
  $scope.status = Wallet.status
  
  $scope.origins = []
  $scope.destinations = []  
  
  $scope.originsLoaded = false
  
  $scope.sending = false # Sending in progress
  
  $scope.$watch "status.didLoadBalances + status.legacyAddressBalancesLoaded", ->
    if $scope.status.didLoadBalances && $scope.status.legacyAddressBalancesLoaded
      if $scope.origins.length == 0      
        for account in $scope.accounts
          item = angular.copy(account)
          item.type = "Accounts" 
          $scope.origins.push item
          $scope.destinations.push item
  
        for address in $scope.legacyAddresses 
          if address.active
            item = angular.copy(address)
            item.type = "Imported Addresses"
            $scope.destinations.push item
            unless address.isWatchOnlyLegacyAddress
              $scope.origins.push item
              
        $scope.originsLoaded = true
    
  # for address, label of $scope.addressBook
  #     item = {address: address, label: label}
  #     item.type = "Address book"
  #     $scope.destinations.push item
  
  # $scope.privacyGuard = false
    
  $scope.errors = {to: null, amount: null}
  
  $scope.alerts = Wallet.alerts
  
  $scope.isOpen = {currencies: false}
  
  $scope.internal = false
  
  $scope.currencies = angular.copy(Wallet.currencies)
  
  for currency in $scope.currencies
    currency.type = "Fiat"
    
  btc = {code: "BTC", type: "Crypto"}  
  $scope.currencies.unshift btc
        
  $scope.BTCtoFiat = (amount, currency) ->
    Wallet.BTCtoFiat(amount, currency)
  
  $scope.setMethod = (method) ->
    $scope.method = method
    
    $scope.errors.to = null
    if paymentRequest.address?
      $scope.transaction.destination = paymentRequest.address
    else if paymentRequest.toAccount?
      $scope.internal = true
      $scope.transaction.destination = paymentRequest.toAccount
      $scope.transaction.from = paymentRequest.fromAddress
      
    return
      
  $scope.maxAndLabel = (select) ->
    return "" unless select?
    return "" unless select.selected?
    
    origin = select.selected
    
    if origin.balance == undefined
      return origin.label
    
    fees = Wallet.recommendedTransactionFee(origin, origin.balance)

    max_btc = numeral(origin.balance - fees).divide("100000000")
    if $scope.transaction.currency == "BTC"
      return origin.label + "(" + max_btc.format("0.[00000000]") + " BTC)"  
    else 
      return origin.label + "(" + $scope.BTCtoFiat(max_btc, $scope.transaction.currency) + " " + $scope.transaction.currency + ")"
  
  $scope.transaction = {from: null, to: paymentRequest.address, destination: null, amount: paymentRequest.amount, satoshi: 0, currency: "BTC", currencySelected: btc, fee: 0}
    
  $scope.setMethod("BTC")
  
    

  $scope.onError = (error) -> 
    # This never gets called...
    $translate("CAMERA_PERMISSION_DENIED").then (translation) ->
      Wallet.displayWarning(translation)
    
  $scope.processURLfromQR = (url) ->
    paymentRequest = Wallet.parsePaymentRequest(url)
    if paymentRequest.isValid
      $scope.transaction.to = paymentRequest.address
      $scope.transaction.amount = paymentRequest.amount if paymentRequest.amount
      $scope.transaction.currency = paymentRequest.currency if paymentRequest.currency

      $scope.cameraOff()
      $scope.visualValidate()
    else
      $translate("QR_CODE_NOT_BITCOIN").then (translation) ->
        Wallet.displayWarning(translation)

      $log.error "Not a bitcoin QR code:" + url
      
      $timeout((->
        $scope.lookForQR()
      ), 2000)
   
  qrcode.callback = $scope.processURLfromQR
  
  $scope.cameraOn = () ->
    $scope.cameraRequested = true
    
  $scope.cameraOff = () ->
    # $scope.qrStream.stop()
    $scope.cameraIsOn = false
    $scope.cameraRequested = false      
  
  $scope.close = () ->
    Wallet.clearAlerts()
    $modalInstance.dismiss ""
  
  $scope.send = () ->
    unless $scope.sending # send() gets called twice for some reason
      $scope.sending = true
    
      transactionDidFailWithError = (message) ->
        Wallet.displayError(message)
        $scope.sending = false
      
      transactionDidFinish = () ->
        sound = ngAudio.load("beep.wav")
        sound.play()
        $scope.sending = false
        $modalInstance.close ""
        $state.go("transactions", {accountIndex: $scope.transaction.from.index })
    
      Wallet.clearAlerts()
    
      if $scope.internal
        fromAccountIdx = $scope.accounts.indexOf($scope.transaction.from) 
        amount = numeral($scope.transaction.amount)
      
        Wallet.sendInternal($scope.transaction.from, $scope.transaction.destination, amount, $scope.transaction.currency, transactionDidFinish, transactionDidFailWithError)
      else
        if $scope.method == "EMAIL" 
          Wallet.sendToEmail($scope.accounts.indexOf($scope.transaction.from), $scope.transaction.to, numeral($scope.transaction.amount), $scope.transaction.currency, transactionDidFinish, transactionDidFailWithError)
          return
        if $scope.method == "SMS"
          Wallet.displayError("SMS not yet supported")
          return
      
        Wallet.send($scope.transaction.from, $scope.transaction.to, numeral($scope.transaction.amount), $scope.transaction.currency, transactionDidFinish, transactionDidFailWithError)

  $scope.closeAlert = (alert) ->
    Wallet.closeAlert(alert)
    
  #################################
  #           Private             #
  #################################
  
  $scope.$watch "transaction.currencySelected", (currency) ->
    if currency?
      $scope.transaction.currency = $scope.transaction.currencySelected.code
      $scope.$$postDigest(()->
        $scope.visualValidate('currency')
      )
  
  $scope.$watchCollection "destinations", () ->
    idx = Wallet.getDefaultAccountIndex()
    if !$scope.transaction.from? && $scope.accounts.length > 0
      if $stateParams.accountIndex == "accounts" || !$stateParams.accountIndex? # The latter is for Jasmine
        # Nothing to do, just use the default index
      else 
        idx = parseInt($stateParams.accountIndex)
      $scope.transaction.from = $scope.accounts[idx]

    if (!$scope.transaction.destination? || $scope.transaction.destination == "") && $scope.destinations.length > 1
      # Destination is ignored unless it's an internal spend
      if idx == 0
        $scope.transaction.destination = $scope.destinations[1]
      else
        $scope.transaction.destination = $scope.destinations[0]
          
  $scope.$watchCollection "[transaction.to, transaction.destination, transaction.from, transaction.amount, transaction.currency]", () ->
    if $scope.transaction.currency == "BTC"
      $scope.transaction.satoshi = parseInt(numeral($scope.transaction.amount).multiply(100000000).format("0"))
    else
      $scope.transaction.satoshi = Wallet.fiatToSatoshi($scope.transaction.amount, $scope.transaction.currency)
    
    if ((!$scope.internal && $scope.transaction.to?) || ($scope.internal && $scope.transaction.destination?)) && $scope.transaction.amount > 0
      $scope.transaction.fee = Wallet.recommendedTransactionFee($scope.transaction.from, $scope.transaction.satoshi)     
      $scope.transactionIsValid = $scope.validate()
    else
      $scope.transactionIsValid = false
    
  $scope.$watch "transaction.from", () ->
    if $scope.transaction.from?
      $scope.from = $scope.transaction.from.label + " Account"
      $scope.visualValidate("from")
    
  $scope.$watch "internal", () ->
    $scope.updateToLabel()
    
  $scope.$watch "transaction.toAccount", ()->
    if $scope.internal      
      $scope.updateToLabel()
      $scope.visualValidate("toAccount")
      $scope.transactionIsValid = $scope.validate()
      
  $scope.$watch "transaction.to", () ->
    if !$scope.internal
      $scope.updateToLabel()
      $scope.transactionIsValid = $scope.validate()
      
  $scope.updateToLabel = () ->
    if $scope.internal
      $scope.toLabel = $scope.transaction.destination.label
      if $scope.transaction.destination.index?
        $scope.toLabel += " Account"
    else
      $scope.toLabel = $scope.transaction.to
      
    
  $scope.visualValidate = (blurredField) ->
    if blurredField == "to"
      $scope.errors.to = null
    
    if blurredField == "amount" || blurredField == "currency"
      $scope.errors.amount = null
  
    transaction = $scope.transaction
    if $scope.internal
      
    else
      unless transaction.to? && transaction.to != ""
        if transaction.amount > 0 && blurredField == "to"
          if $scope.method == "BTC"
            $scope.errors.to = "Bitcoin address missing"
          else if $scope.method == "EMAIL"
            $scope.errors.to = "Email address missing"
          else if $scope.method == "SMS"
            $scope.errors.to = "Mobile phone number missing"
    
      unless transaction.to == ""
        if $scope.method == "BTC"
          unless Wallet.isValidAddress(transaction.to)
            if blurredField == "to"
              $scope.errors.to = "Invalid bitcoin address"
        else if $scope.method == "EMAIL"
          unless $scope.transaction.to.indexOf("@") > -1 && $scope.transaction.to.indexOf(".") > -1
            if blurredField == "to"
              $scope.errors.to = "Invalid email address"   
        else if $scope.method == "SMS"
          unless true
            if blurredField == "to"
              $scope.errors.to = "Invalid international phone number."   
              
    
    unless transaction.amount? && transaction.amount > 0
      if blurredField == "amount" 
        $scope.errors.amount = "Please enter amount"

    if $scope.originsLoaded && transaction.amount > 0 && !$scope.validateAmount()
      if blurredField == "amount" || blurredField == "from" || blurredField == "currency"
        $scope.errors.amount = "Insufficient funds"
    
    return 
    
  $scope.$watch "originsLoaded", ->
    $scope.transactionIsValid = $scope.validate()
    if $scope.transaction.amount? && $scope.transaction.amount > 0
      $scope.visualValidate("amount")
    
  $scope.validate = () ->    
    return false unless $scope.originsLoaded
  
    transaction = $scope.transaction
        
    if $scope.internal
      return false if transaction.destination == transaction.from
    else
      unless transaction.to? && transaction.to != ""
        return false
            
      if $scope.method == "BTC"
        unless Wallet.isValidAddress(transaction.to)
          return false
      else if $scope.method == "EMAIL"
        return false unless $scope.transaction.to.indexOf("@") > -1 && $scope.transaction.to.indexOf(".") > -1
      # else if $scope.method == "SMS"
    
    $scope.errors.to = null
    
    return false unless $scope.validateAmount()   
    return true
    
  $scope.validateAmount = () ->
    amount = $scope.transaction.amount

    return false unless amount? && amount > 0      
    
    return false unless $scope.transaction.from? && $scope.transaction.from.balance?
    
    return false if $scope.transaction.satoshi + $scope.transaction.fee > $scope.transaction.from.balance
    $scope.errors.amount = null
    return true
    
  
  $scope.goToConfirmation = () ->
    $scope.confirmationStep = true
    
  $scope.backToForm = () ->
    $scope.confirmationStep = false    
    
  $scope.switchToExternal = () ->
    $scope.internal = false
    
  $scope.switchToInternal = () ->
    $scope.internal = true