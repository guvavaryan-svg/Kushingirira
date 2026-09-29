//+------------------------------------------------------------------+
//|    RUHAAN_FX_Sniper_Matrix_v6.5.3_FINAL_FIXED.mq5                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026 - RUHAAN FX"
#property version   "6.53"

#include <Trade\Trade.mqh>
CTrade trade;

// --- Magic Number & Identification ---
input ulong    MagicNumber          = 51399;  // Unique Magic Number for this Chart

// --- EMA & Strategy Inputs ---
input int      FastEMAPeriod        = 8;      // Fast EMA Period
input int      SlowEMAPeriod        = 13;     // Slow EMA Period
input int      SRLookbackBars       = 20;     // Support & Resistance Lookback Bars
input double   PullbackBufferPts    = 150;    // Pullback Max Distance from EMA (Points)
input double   TakeProfitTarget     = 0.30;   // OPTIMIZED FOR $20: Target Profit ($0.30 = 1.5%)
input double   MaxAllowedLoss       = 0.50;   // OPTIMIZED FOR $20: Hard Loss Cap ($0.50 = 2.5%)

// --- Multi-Timeframe (MTF) Trend Filter Inputs ---
input bool     UseMTFFilter         = true;   // Enable Higher Timeframe Trend Alignment
input ENUM_TIMEFRAMES HTFTimeframe  = PERIOD_M15; // Higher Timeframe (e.g. M15)

// --- Dynamic Lot Sizing & Risk Management ---
input bool     UseAutoLot           = false;  // Enable Auto Lot Size based on Risk %
input double   RiskPercent          = 0.5;    // Risk % of Equity per trade (if Auto Lot is true)
input double   FixedLotSize         = 0.01;   // Base Fixed Lot Size (if Auto Lot is false)

// --- Partial TP & Break-Even Settings ---
input bool     UsePartialTP         = true;   // Enable Partial Close & Break-Even
input double   PartialTPProfit      = 0.10;   // OPTIMIZED FOR $20: Profit Target ($0.10) to lock BE
input double   BreakEvenOffset      = 30;     // OPTIMIZED FOR $20: Lock Profit above Entry (30 Pts = $0.03)

// --- Trailing Stop Loss Settings ---
input bool     UseTrailingStop      = true;   // Enable Trailing Stop Loss
input double   TrailingStartPts     = 80;     // OPTIMIZED FOR $20: Points in Profit to Start Trailing
input double   TrailingStepPts      = 25;     // OPTIMIZED FOR $20: Trailing Distance Step (Points)

// --- Trading Session Time Filter ---
input bool     UseSessionFilter     = false;  // Enable Time Session Filter
input int      StartHour            = 7;      // Start Hour (Server Time e.g., 07:00 London)
input int      EndHour              = 20;     // End Hour (Server Time e.g., 20:00 NY Close)

// --- ADX Trend Filter Inputs ---
input bool     UseADXFilter         = true;   // Enable ADX Trend Filter
input int      ADXPeriod            = 14;     // ADX Period
input double   MinADXThreshold      = 22.0;   // OPTIMIZED FOR $20: Min ADX Level (Avoid Ranging Market)

// --- Dynamic Grid Step & Dynamic TP Inputs ---
input bool     UseSmartGrid         = true;   // Enable Smart Safety Grid
input bool     UseDynamicGridTP     = true;   // Enable Dynamic Target Profit
input double   DynamicMultiplier    = 1.0;    // TP Scaling Factor Per Grid Level
input bool     UseDynamicATRStep    = true;   // Enable Dynamic ATR Grid Step
input double   ATRStepMultiplier    = 1.5;    // ATR Step Multiplier (ATR * Multiplier)
input int      GridStepPoints       = 200;    // OPTIMIZED FOR $20: Minimum Grid Distance (20 pips)
input int      MaxGridOrders        = 2;      // OPTIMIZED FOR $20: Max Grid Trades (Safety Limit)

// --- Spike Filter Input ---
input bool     UseSpikeBlock        = true;   // Block Trades on Giant Candle Spikes
input double   MaxCandleSpikePts    = 350;    // Max Allowed Candle Size (Points)

// --- News Filter Inputs ---
input bool     UseNewsFilter        = true;   // Enable High-Impact News Filter
input int      NewsPauseBefore      = 15;     // Pause Trading (Minutes BEFORE News)
input int      NewsPauseAfter       = 15;     // Pause Trading (Minutes AFTER News)

// --- Fast Execution & Broker Sync Inputs ---
input ulong    MaxSlippagePoints    = 35;     // Max Allowed Slippage/Deviation (Points)
input int      MaxSpreadPoints      = 35;     // Maximum Allowed Spread (Points)

// --- Daily Loss Percentage & Dynamic Cap ---
input double   MaxDailyLossPercent  = 12.5;   // Daily Loss Percentage Limit
input double   MaxDailyLossUSD      = 2.00;   // OPTIMIZED FOR $20: Daily Hard Loss Limit ($2.00)
input double   MaxDailyProfit       = 3.00;   // OPTIMIZED FOR $20: Daily Target Profit Cap ($3.00)

input bool     UseATRFilter         = true;   // Enable ATR Volatility Filter
input int      ATRPeriod            = 14;     // ATR Period
input double   MinATRValue          = 0.00008;// OPTIMIZED FOR M5/EURUSD
input bool     SendPhoneAlerts      = true;   // Send Push Notifications To Mobile

// --- Dashboard Customization Inputs ---
input color    BgColor              = C'25,28,36';   // Dark Grey Background Color
input color    BorderColor          = C'60,68,85';   // Panel Border Color
input color    TitleColor           = C'255,215,0';  // Gold Title Color
input color    TextColor            = C'220,225,230';// Main Text Color
input color    StatusColor          = C'50,205,50';  // Status Accent Color (Lime Green)

// --- Global Handles & Variables ---
int      fastEMA_handle, slowEMA_handle, atr_handle, adx_handle;
int      htfFastEMA_handle, htfSlowEMA_handle;
string   currentStatus        = "STUDYING MARKET...";
datetime lastTradeBarTime;
double   dailyLossTotal       = 0.0;
double   dailyProfitTotal     = 0.0;
datetime lastDailyReset;
bool     partialClosed        = false;

// --- Network Protection Variables ---
datetime lastExecutionTime    = 0;
int      consecutiveErrors    = 0;
datetime cooldownExpiry       = 0;

//+------------------------------------------------------------------+
//| FIX 1: Calculate Dynamic Daily Loss Threshold (Corrected)        |
//+------------------------------------------------------------------+
double GetEffectiveDailyLossLimit()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 25.0) return MaxDailyLossUSD; // $20 account = $2.00 max
   return MaxDailyLossUSD * 2.0;              // Account hombe max $4.00 hard stop
}

//+------------------------------------------------------------------+
//| Calculate Calculated Lot Size (Auto Lot or Fixed)               |
//+------------------------------------------------------------------+
double GetCalculatedLotSize()
{
   if(!UseAutoLot) return FixedLotSize;

   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double minLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(tickVal <= 0) return FixedLotSize;

   double riskAmount = equity * (RiskPercent / 100.0);
   double calculated = (riskAmount / (MaxAllowedLoss * 100));

   double stepLot = MathFloor(calculated / lotStep) * lotStep;
   if(stepLot < minLot) stepLot = minLot;
   if(stepLot > maxLot) stepLot = maxLot;

   return stepLot;
}

//+------------------------------------------------------------------+
//| Check Higher Timeframe (M15) Trend Alignment                     |
//+------------------------------------------------------------------+
int GetHTFTrend()
{
   if(!UseMTFFilter) return 0;

   double htfFast[], htfSlow[];
   ArraySetAsSeries(htfFast, true);
   ArraySetAsSeries(htfSlow, true);

   if(CopyBuffer(htfFastEMA_handle, 0, 1, 1, htfFast) < 1) return 0;
   if(CopyBuffer(htfSlowEMA_handle, 0, 1, 1, htfSlow) < 1) return 0;

   if(htfFast[0] > htfSlow[0]) return 1;   // Bullish
   if(htfFast[0] < htfSlow[0]) return -1;  // Bearish

   return 0;
}

//+------------------------------------------------------------------+
//| Check Trading Session Time                                       |
//+------------------------------------------------------------------+
bool IsInTradingSession()
{
   if(!UseSessionFilter) return true;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   if(StartHour <= EndHour)
      return (dt.hour >= StartHour && dt.hour < EndHour);
   else
      return (dt.hour >= StartHour || dt.hour < EndHour);
}

//+------------------------------------------------------------------+
//| Get Support & Resistance Levels                                 |
//+------------------------------------------------------------------+
void GetSupportResistance(double &support, double &resistance)
{
   int highestBar = iHighest(_Symbol, _Period, MODE_HIGH, SRLookbackBars, 1);
   int lowestBar  = iLowest(_Symbol, _Period, MODE_LOW, SRLookbackBars, 1);

   resistance = iHigh(_Symbol, _Period, highestBar);
   support    = iLow(_Symbol, _Period, lowestBar);
}

//+------------------------------------------------------------------+
//| Dynamic Target Profit Engine                                    |
//+------------------------------------------------------------------+
double CalculateDynamicTargetProfit(int openCount)
{
   if(openCount <= 0) return TakeProfitTarget;
   if(!UseDynamicGridTP) return TakeProfitTarget;

   double calculatedTP = TakeProfitTarget * (1.0 + ((openCount - 1) * DynamicMultiplier));
   if(calculatedTP <= 0.0) return TakeProfitTarget;
   
   return NormalizeDouble(calculatedTP, 2);
}

//+------------------------------------------------------------------+
//| Dynamic ATR Step Distance Calculator                             |
//+------------------------------------------------------------------+
double GetCurrentGridStepDistance()
{
   double basePointsDistance = GridStepPoints * _Point;

   if(!UseDynamicATRStep) return basePointsDistance;

   double atr[];
   ArraySetAsSeries(atr, true);
   
   if(CopyBuffer(atr_handle, 0, 1, 1, atr) > 0 && atr[0] > 0)
   {
      double calculatedStep = atr[0] * ATRStepMultiplier;
      if(calculatedStep < basePointsDistance) return basePointsDistance;
      return calculatedStep;
   }

   return basePointsDistance;
}

//+------------------------------------------------------------------+
//| Auto-Configure Broker Execution Settings                         |
//+------------------------------------------------------------------+
void SetBrokerExecutionSettings()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxSlippagePoints);
   trade.SetAsyncMode(false);
   
   uint fillType = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fillType & SYMBOL_FILLING_IOC) != 0)
      trade.SetTypeFilling(ORDER_FILLING_IOC);
   else if((fillType & SYMBOL_FILLING_FOK) != 0)
      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else
      trade.SetTypeFilling(ORDER_FILLING_RETURN);
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   SetBrokerExecutionSettings();

   // Chart Timeframe Handles
   fastEMA_handle = iMA(_Symbol, _Period, FastEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   slowEMA_handle = iMA(_Symbol, _Period, SlowEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   atr_handle     = iATR(_Symbol, _Period, ATRPeriod);
   adx_handle     = iADX(_Symbol, _Period, ADXPeriod);

   // Higher Timeframe Handles (M15 MTF)
   htfFastEMA_handle = iMA(_Symbol, HTFTimeframe, FastEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   htfSlowEMA_handle = iMA(_Symbol, HTFTimeframe, SlowEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   
   if(fastEMA_handle == INVALID_HANDLE || slowEMA_handle == INVALID_HANDLE || 
      atr_handle == INVALID_HANDLE || adx_handle == INVALID_HANDLE ||
      htfFastEMA_handle == INVALID_HANDLE || htfSlowEMA_handle == INVALID_HANDLE)
   {
      Print("Error: Failed to initialize indicator handles.");
      return(INIT_FAILED);
   }
   
   lastDailyReset    = TimeCurrent();
   currentStatus     = "STUDYING MARKET...";
   consecutiveErrors = 0;
   partialClosed     = false;

   EventSetTimer(1);
   DrawGraphicalDashboard(); 

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteDashboardObjects();
   IndicatorRelease(fastEMA_handle);
   IndicatorRelease(slowEMA_handle);
   IndicatorRelease(atr_handle);
   IndicatorRelease(adx_handle);
   IndicatorRelease(htfFastEMA_handle);
   IndicatorRelease(htfSlowEMA_handle);
}

void OnTimer()
{
   DrawGraphicalDashboard();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   DrawGraphicalDashboard();
}

//+------------------------------------------------------------------+
//| High Impact News Calendar Check (Both Base & Profit Currencies)  |
//+------------------------------------------------------------------+
bool IsHighImpactNewsTime()
{
   if(!UseNewsFilter) return false;

   MqlCalendarValue valuesBase[], valuesProfit[];
   datetime fromTime = TimeCurrent() - (NewsPauseAfter * 60);
   datetime toTime   = TimeCurrent() + (NewsPauseBefore * 60);

   string baseCurrency   = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
   string profitCurrency = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
   
   if(CalendarValueHistory(valuesBase, fromTime, toTime, baseCurrency, NULL) > 0)
   {
      for(int i = 0; i < ArraySize(valuesBase); i++)
      {
         MqlCalendarEvent event;
         if(CalendarEventById(valuesBase[i].event_id, event))
         {
            if(event.importance == CALENDAR_IMPORTANCE_HIGH) return true;
         }
      }
   }

   if(CalendarValueHistory(valuesProfit, fromTime, toTime, profitCurrency, NULL) > 0)
   {
      for(int i = 0; i < ArraySize(valuesProfit); i++)
      {
         MqlCalendarEvent event;
         if(CalendarEventById(valuesProfit[i].event_id, event))
         {
            if(event.importance == CALENDAR_IMPORTANCE_HIGH) return true;
         }
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Safe Order Execution Engine                                      |
//+------------------------------------------------------------------+
bool SafeExecuteTrade(ENUM_ORDER_TYPE orderType, double requestedLots, string comment)
{
   if(TimeCurrent() < cooldownExpiry)
   {
      currentStatus = "COOLDOWN ACTIVE (" + IntegerToString((int)(cooldownExpiry - TimeCurrent())) + "s)";
      return false;
   }

   if(TimeCurrent() - lastExecutionTime < 3) return false;

   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
   {
      currentStatus = "PAUSED: No Terminal Connection";
      return false;
   }

   if(consecutiveErrors >= 5)
   {
      currentStatus = "COOLDOWN INITIATED (30s Pause)";
      cooldownExpiry = TimeCurrent() + 30;
      consecutiveErrors = 0;
      return false;
   }

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   double safeVolume = MathFloor(requestedLots / lotStep) * lotStep;
   if(safeVolume < minLot) safeVolume = minLot;
   if(safeVolume > maxLot) safeVolume = maxLot;

   bool success = false;

   for(int attempt = 1; attempt <= 3; attempt++)
   {
      if(orderType == ORDER_TYPE_BUY)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         ask = NormalizeDouble(ask, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
         success = trade.Buy(safeVolume, _Symbol, ask, 0, 0, comment);
      }
      else if(orderType == ORDER_TYPE_SELL)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         bid = NormalizeDouble(bid, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
         success = trade.Sell(safeVolume, _Symbol, bid, 0, 0, comment);
      }

      if(success) break;
      Sleep(200);
   }

   lastExecutionTime = TimeCurrent();

   if(!success)
   {
      consecutiveErrors++;
      Print("Broker rejected order! Code: ", trade.ResultRetcode(), " Desc: ", trade.ResultRetcodeDescription());
      return false;
   }

   consecutiveErrors = 0;
   return true;
}

//+------------------------------------------------------------------+
//| FIX 2: Partial TP & Break-Even Logic Engine (Corrected)          |
//+------------------------------------------------------------------+
void ProcessPartialTPAndBreakEven()
{
   if(!UsePartialTP) return;
   double basketProfit = GetBasketProfit();
   if(basketProfit < PartialTPProfit) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         double currentVol = PositionGetDouble(POSITION_VOLUME);
         double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         
         double beSL = (posType == POSITION_TYPE_BUY) ? 
                       openPrice + (BreakEvenOffset * _Point) : 
                       openPrice - (BreakEvenOffset * _Point);
         beSL = NormalizeDouble(beSL, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));

         // Pa $20 account - 0.01 lot haigone kuita partial, isa BE chete
         if(currentVol <= minLot + 0.0001)
         {
            if(!partialClosed)
            {
               trade.PositionModify(ticket, beSL, PositionGetDouble(POSITION_TP));
               partialClosed = true;
               currentStatus = "BREAK-EVEN LOCKED (+$0.03) - $20 SAFE";
               SendAlert("Break-Even Locked for $20 Account");
            }
            return;
         }

         // Pa lot hombe chete ndipo panoita partial
         double halfVol = NormalizeDouble(currentVol / 2.0, 2);
         if(halfVol >= minLot && !partialClosed)
         {
            if(trade.PositionClosePartial(ticket, halfVol))
            {
               partialClosed = true;
               trade.PositionModify(ticket, beSL, PositionGetDouble(POSITION_TP));
               currentStatus = "PARTIAL TP SECURED: 50% Closed + BE";
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Trailing Stop Loss Engine                                        |
//+------------------------------------------------------------------+
void ProcessTrailingStop()
{
   if(!UseTrailingStop) return;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double startPtsDistance = TrailingStartPts * _Point;
   double stepPtsDistance  = TrailingStepPts * _Point;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL  = PositionGetDouble(POSITION_SL);

         if(posType == POSITION_TYPE_BUY)
         {
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            if(ask - openPrice >= startPtsDistance)
            {
               double newSL = NormalizeDouble(ask - stepPtsDistance, digits);
               if(newSL > currentSL)
               {
                  trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
                  currentStatus = "TRAILING SL UPDATED (BUY)";
               }
            }
         }
         else if(posType == POSITION_TYPE_SELL)
         {
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            if(openPrice - bid >= startPtsDistance)
            {
               double newSL = NormalizeDouble(bid + stepPtsDistance, digits);
               if(currentSL == 0 || newSL < currentSL)
               {
                  trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
                  currentStatus = "TRAILING SL UPDATED (SELL)";
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
   {
      currentStatus = "PAUSED: No Terminal Connection";
      return;
   }

   ResetDailyLimitsIfNeeded();
   ManagePositionsAndBasket();
   ProcessPartialTPAndBreakEven();
   ProcessTrailingStop();

   double activeDailyLossLimit = GetEffectiveDailyLossLimit();

   if(dailyLossTotal >= activeDailyLossLimit)
   {
      currentStatus = "STOPPED: Daily Loss Hit (-$" + DoubleToString(dailyLossTotal, 2) + " / Max $" + DoubleToString(activeDailyLossLimit, 2) + ")";
      return;
   }

   if(dailyProfitTotal >= MaxDailyProfit)
   {
      currentStatus = "TARGET REACHED: Daily Target Hit (+$" + DoubleToString(dailyProfitTotal, 2) + ")";
      return;
   }

   if(!IsInTradingSession())
   {
      currentStatus = "PAUSED: Outside Trading Session (" + IntegerToString(StartHour) + ":00-" + IntegerToString(EndHour) + ":00)";
      return;
   }

   if(IsHighImpactNewsTime())
   {
      currentStatus = "PAUSED: High Impact News Event";
      return;
   }

   long currentSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(currentSpread > MaxSpreadPoints)
   {
      currentStatus = "PAUSED: High Spread (" + IntegerToString(currentSpread) + " pts)";
      return;
   }

   // --- BIG CANDLE SPIKE FILTER ---
   if(UseSpikeBlock)
   {
      double high1 = iHigh(_Symbol, _Period, 1);
      double low1  = iLow(_Symbol, _Period, 1);
      double candleSizePts = (high1 - low1) / _Point;

      if(candleSizePts > MaxCandleSpikePts)
      {
         currentStatus = "PAUSED: Big Spike Block (" + DoubleToString(candleSizePts, 0) + " pts)";
         return;
      }
   }

   if(UseATRFilter)
   {
      double atr[];
      ArraySetAsSeries(atr, true);
      if(CopyBuffer(atr_handle, 0, 1, 1, atr) > 0)
      {
         if(atr[0] < MinATRValue)
         {
            currentStatus = "IDLE: Low Volatility (ATR)";
            return;
         }
      }
   }

   // --- ADX FILTER CHECK ---
   double adxValues[];
   ArraySetAsSeries(adxValues, true);
   if(UseADXFilter)
   {
      if(CopyBuffer(adx_handle, 0, 1, 1, adxValues) > 0)
      {
         if(adxValues[0] < MinADXThreshold)
         {
            currentStatus = "PAUSED: ADX Low (" + DoubleToString(adxValues[0], 1) + " < " + DoubleToString(MinADXThreshold, 1) + ")";
            return;
         }
      }
   }

   // --- NO REPAINT: SHIFT 1 CLOSED CANDLE EXECUTION ---
   double fastEMA[], slowEMA[];
   ArraySetAsSeries(fastEMA, true);
   ArraySetAsSeries(slowEMA, true);
   
   if(CopyBuffer(fastEMA_handle, 0, 1, 2, fastEMA) < 2) return;
   if(CopyBuffer(slowEMA_handle, 0, 1, 2, slowEMA) < 2) return;

   double currentFast = fastEMA[0]; // Bar 1 (Closed Candle)
   double currentSlow = slowEMA[0];
   double prevFast    = fastEMA[1]; // Bar 2
   double prevSlow    = slowEMA[1];

   double supportLevel = 0.0, resistanceLevel = 0.0;
   GetSupportResistance(supportLevel, resistanceLevel);

   double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double bufferDistance = PullbackBufferPts * _Point;

   // Signal Detection
   bool emaBuyTrend  = (prevFast <= prevSlow && currentFast > currentSlow);
   bool emaSellTrend = (prevFast >= prevSlow && currentFast < currentSlow);

   bool buyPullback  = (currentFast > currentSlow) && (currentAsk > supportLevel) && (MathAbs(currentAsk - currentFast) <= bufferDistance);
   bool sellPullback = (currentFast < currentSlow) && (currentBid < resistanceLevel) && (MathAbs(currentBid - currentFast) <= bufferDistance);

   // --- MULTI-TIMEFRAME ALIGNMENT CHECK ---
   int htfTrend = GetHTFTrend();

   int buyPositions = 0, sellPositions = 0;
   GetPositionTypesCount(buyPositions, sellPositions);
   
   double currentBasketProfit = GetBasketProfit();
   datetime currentBarTime = iTime(_Symbol, _Period, 0);

   double tradeLot = GetCalculatedLotSize();

   // BUY Signal Execution (Must Match M15 Bullish Trend)
   if((emaBuyTrend || buyPullback) && (currentFast > currentSlow))
   {
      if(UseMTFFilter && htfTrend != 1)
      {
         currentStatus = "PAUSED: Buy Signal Blocked by M15 Bearish Trend";
         return;
      }

      if(sellPositions > 0 && currentBasketProfit >= -0.10)
      {
         CloseAllSymbolPositions();
         currentStatus = "REVERSING: Closed SELL on BUY Signal";
      }

      if(GetCurrentSymbolPositions() == 0 && currentBarTime != lastTradeBarTime)
      {
         if(SafeExecuteTrade(ORDER_TYPE_BUY, tradeLot, "Sniper Buy v6.5.3"))
         {
            lastTradeBarTime = currentBarTime;
            partialClosed    = false;
            SendAlert("CLOSED CANDLE BUY Open on " + _Symbol);
         }
      }
   }
   // SELL Signal Execution (Must Match M15 Bearish Trend)
   else if((emaSellTrend || sellPullback) && (currentFast < currentSlow))
   {
      if(UseMTFFilter && htfTrend != -1)
      {
         currentStatus = "PAUSED: Sell Signal Blocked by M15 Bullish Trend";
         return;
      }

      if(buyPositions > 0 && currentBasketProfit >= -0.10)
      {
         CloseAllSymbolPositions();
         currentStatus = "REVERSING: Closed BUY on SELL Signal";
      }

      if(GetCurrentSymbolPositions() == 0 && currentBarTime != lastTradeBarTime)
      {
         if(SafeExecuteTrade(ORDER_TYPE_SELL, tradeLot, "Sniper Sell v6.5.3"))
         {
            lastTradeBarTime = currentBarTime;
            partialClosed    = false;
            SendAlert("CLOSED CANDLE SELL Open on " + _Symbol);
         }
      }
   }
   else if(UseSmartGrid && GetCurrentSymbolPositions() > 0 && GetCurrentSymbolPositions() < MaxGridOrders)
   {
      currentStatus = "GRID ACTIVE (" + IntegerToString(GetCurrentSymbolPositions()) + "/" + IntegerToString(MaxGridOrders) + ")";
      CheckAndExecuteGrid();
   }
   else if(GetCurrentSymbolPositions() == 0)
   {
      currentStatus = "STUDYING MARKET (Waiting for Closed Candle Crossovers)...";
   }
}

//+------------------------------------------------------------------+
//| Get Current Basket Profit                                        |
//+------------------------------------------------------------------+
double GetBasketProfit()
{
   double profit = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         profit += PositionGetDouble(POSITION_PROFIT);
      }
   }
   return profit;
}

//+------------------------------------------------------------------+
//| Management Logic with Dynamic Grid TP Engine                     |
//+------------------------------------------------------------------+
void ManagePositionsAndBasket()
{
   int openCount = GetCurrentSymbolPositions();
   double basketProfit = GetBasketProfit();

   if(openCount > 0)
   {
      double dynamicTP = CalculateDynamicTargetProfit(openCount);

      if(basketProfit >= dynamicTP)
      {
         CloseAllSymbolPositions();
         currentStatus = "CLOSED: Target Hit (+$" + DoubleToString(basketProfit, 2) + ")";
         SendAlert("Profit Target Secured: $" + DoubleToString(basketProfit, 2));
      }
      else if(basketProfit <= -MaxAllowedLoss)
      {
         CloseAllSymbolPositions();
         currentStatus = "CLOSED: Hard Loss Hit (-$" + DoubleToString(MathAbs(basketProfit), 2) + ")";
         SendAlert("Closed with Loss: -$" + DoubleToString(MathAbs(basketProfit), 2));
      }
   }
}

//+------------------------------------------------------------------+
//| Grid Trade Execution using Dynamic ATR Step & GridStepPoints     |
//+------------------------------------------------------------------+
void CheckAndExecuteGrid()
{
   ulong lastTicket = 0;
   datetime lastTime = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         datetime pTime = (datetime)PositionGetInteger(POSITION_TIME);
         if(pTime > lastTime)
         {
            lastTime = pTime;
            lastTicket = ticket;
         }
      }
   }

   if(lastTicket > 0 && PositionSelectByTicket(lastTicket))
   {
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);

      double requiredStepDistance = GetCurrentGridStepDistance();
      double tradeLot = GetCalculatedLotSize();

      if(posType == POSITION_TYPE_BUY)
      {
         double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(openPrice - currentAsk >= requiredStepDistance) 
            SafeExecuteTrade(ORDER_TYPE_BUY, tradeLot, "Grid Buy (ATR Step)");
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(currentBid - openPrice >= requiredStepDistance) 
            SafeExecuteTrade(ORDER_TYPE_SELL, tradeLot, "Grid Sell (ATR Step)");
      }
   }
}

//+------------------------------------------------------------------+
//| Close All Positions + Track Loss/Profit                          |
//+------------------------------------------------------------------+
void CloseAllSymbolPositions()
{
   double closingProfit = GetBasketProfit();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         trade.PositionClose(ticket);
         Sleep(100);
      }
   }

   if(closingProfit < 0)
      dailyLossTotal += MathAbs(closingProfit);
   else
      dailyProfitTotal += closingProfit;

   partialClosed = false;
}

int GetCurrentSymbolPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber) count++;
   }
   return count;
}

void GetPositionTypesCount(int &buyCount, int &sellCount)
{
   buyCount = 0;
   sellCount = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(posType == POSITION_TYPE_BUY) buyCount++;
         if(posType == POSITION_TYPE_SELL) sellCount++;
      }
   }
}

string GetCandleTimeRemaining()
{
   datetime candleStartTime = iTime(_Symbol, _Period, 0);
   int candleDurationSeconds = PeriodSeconds(_Period);
   datetime candleEndTime = candleStartTime + candleDurationSeconds;
   long remainingSeconds = candleEndTime - TimeCurrent();
   if(remainingSeconds < 0) remainingSeconds = 0;
   return StringFormat("%02d:%02d", (int)(remainingSeconds / 60), (int)(remainingSeconds % 60));
}

void ResetDailyLimitsIfNeeded()
{
   MqlDateTime nowStruct, lastStruct;
   TimeToStruct(TimeCurrent(), nowStruct);
   TimeToStruct(lastDailyReset, lastStruct);
   if(nowStruct.day != lastStruct.day)
   {
      dailyLossTotal   = 0.0;
      dailyProfitTotal = 0.0;
      lastDailyReset   = TimeCurrent();
   }
}

void SendAlert(string message)
{
   Print(message);
   PlaySound("alert.wav");
   if(SendPhoneAlerts) SendNotification("EA Alert: " + message);
}

//+------------------------------------------------------------------+
//| Graphical Dashboard Engine                                       |
//+------------------------------------------------------------------+
void DrawGraphicalDashboard()
{
   double balance     = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity      = AccountInfoDouble(ACCOUNT_EQUITY);
   double openProfit  = GetBasketProfit();
   long currentSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   int openCount      = GetCurrentSymbolPositions();

   string bgName = "EMA_Dash_BG_Panel";
   if(ObjectFind(0, bgName) < 0)
   {
      ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, 15);
      ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, 15);
      ObjectSetInteger(0, bgName, OBJPROP_XSIZE, 380);
      ObjectSetInteger(0, bgName, OBJPROP_YSIZE, 285);
      ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, BgColor);
      ObjectSetInteger(0, bgName, OBJPROP_BORDER_COLOR, BorderColor);
      ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bgName, OBJPROP_BACK, false);
      ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);
   }

   double targetDisplay = CalculateDynamicTargetProfit(openCount);
   double currentGridStepPts = GetCurrentGridStepDistance() / _Point;

   double adxVal[];
   ArraySetAsSeries(adxVal, true);
   string adxStr = "N/A";
   if(CopyBuffer(adx_handle, 0, 1, 1, adxVal) > 0)
      adxStr = DoubleToString(adxVal[0], 1);

   int htfTrend = GetHTFTrend();
   string htfStr = (htfTrend == 1) ? "BULLISH" : ((htfTrend == -1) ? "BEARISH" : "DISABLED");
   double activeLimit = GetEffectiveDailyLossLimit();

   string lines[14];
   lines[0]  = "------------------------------------------";
   lines[1]  = " RUHAAN FX - SNIPER MATRIX v6.5.3 ($20)";
   lines[2]  = "------------------------------------------";
   lines[3]  = " Magic / Symbol : " + IntegerToString(MagicNumber) + " | " + _Symbol;
   lines[4]  = " M15 HTF Trend  : " + htfStr;
   lines[5]  = " Lot Size Sizing: " + (UseAutoLot ? ("Auto Risk (" + DoubleToString(RiskPercent, 1) + "%)") : ("Fixed " + DoubleToString(GetCalculatedLotSize(), 2)));
   lines[6]  = " Daily Max Loss : $" + DoubleToString(activeLimit, 2) + " Cap";
   lines[7]  = " Spread / Range : " + IntegerToString(currentSpread) + " pts (Max " + IntegerToString(MaxSpreadPoints) + ")";
   lines[8]  = " Balance / Equity: $" + DoubleToString(balance, 2) + " / $" + DoubleToString(equity, 2);
   lines[9]  = " Target Basket TP: $" + DoubleToString(targetDisplay, 2) + (UseDynamicGridTP ? " (Dynamic)" : " (Fixed)");
   lines[10] = " Active Grid Step: " + DoubleToString(currentGridStepPts, 1) + " pts " + (UseDynamicATRStep ? "(ATR)" : "(Fixed)");
   lines[11] = " Open Positions  : " + IntegerToString(openCount) + " (P/L: $" + DoubleToString(openProfit, 2) + ")";
   lines[12] = " CANDLE TIMER    : " + GetCandleTimeRemaining();
   lines[13] = " STATUS          : " + currentStatus;

   int yDist = 25;
   for(int i = 0; i < 14; i++)
   {
      string objName = "EMA_Dash_Line_" + IntegerToString(i);
      if(ObjectFind(0, objName) < 0)
      {
         ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, 25);
         ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 9);
         ObjectSetString(0, objName, OBJPROP_FONT, "Courier New");
         ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
      }

      ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, yDist);
      ObjectSetString(0, objName, OBJPROP_TEXT, lines[i]);

      if(i == 1) 
         ObjectSetInteger(0, objName, OBJPROP_COLOR, TitleColor);
      else if(i == 13) 
         ObjectSetInteger(0, objName, OBJPROP_COLOR, StatusColor);
      else if(i == 0 || i == 2)
         ObjectSetInteger(0, objName, OBJPROP_COLOR, BorderColor);
      else 
         ObjectSetInteger(0, objName, OBJPROP_COLOR, TextColor);

      yDist += 17;
   }
   ChartRedraw();
}

void DeleteDashboardObjects()
{
   ObjectDelete(0, "EMA_Dash_BG_Panel");
   for(int i = 0; i < 14; i++)
   {
      ObjectDelete(0, "EMA_Dash_Line_" + IntegerToString(i));
   }
   ChartRedraw();
}
