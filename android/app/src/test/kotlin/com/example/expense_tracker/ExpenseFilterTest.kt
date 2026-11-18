package com.example.expense_tracker

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ExpenseFilterTest {

    private fun expense(text: String) =
        assertTrue("should be logged: $text", ExpenseNotificationListener.looksLikeExpense(text))

    private fun notExpense(text: String) =
        assertFalse("should be ignored: $text", ExpenseNotificationListener.looksLikeExpense(text))

    @Test
    fun logsMoneyGoingOut() {
        // Real alerts seen on the device (account details shortened).
        expense("BP-FEDBNK-S: Debited Rs 3.00 from a/c X1234 on 18Nov26 18:33 via UPI to SHOP. Ref 632296920471.Bal Rs 5676.82. -Federal Bank")
        expense("GPay: You paid ₹250 to Swiggy")
        expense("Sent Rs.500 from Kotak Bank AC X1234 to merchant@upi on 18-11-26")
        expense("INR 1,299.00 spent on your HDFC Bank Credit Card XX1234 at AMAZON")
        // Both sides mentioned, debit first -> it's your spend.
        expense("Rs 500 debited from A/c XX1234 and credited to swiggy@icici")
        expense("A/c X1234 debited by Rs 60.00; credited to PETROL PUMP UPI Ref 123")
    }

    @Test
    fun ignoresMoneyComingIn() {
        // The bug: an incoming GPay payment was logged as an expense.
        notExpense("GPay: Mridhul M S paid you ₹1.00: Paid via SuperMoney UPI")
        notExpense("PhonePe: Rahul sent you ₹200")
        notExpense("You have received Rs 500 from Anu on PhonePe")
        notExpense("Received ₹750 from ARJUN via UPI")
        notExpense("Rs 2,000.00 credited to your A/c X1234 by NEFT. -Federal Bank")
        notExpense("Your a/c X1234 has been credited with INR 1000 via UPI")
        // Both sides mentioned, credit first -> money came in.
        notExpense("A/c X1234 credited with Rs 300; debited from sender@okaxis")
    }

    @Test
    fun ignoresNonPayments() {
        notExpense("123456 is your OTP for payment of Rs 500. Do not share.")
        notExpense("Refund of Rs 199 has been processed for your order")
        notExpense("Rs 5000 will be debited from your account on 20 Nov for EMI")
        notExpense("Payment of Rs 300 failed. Money will not be debited.")
        notExpense("Anu requested ₹150 from you on GPay")
        notExpense("Get up to Rs 100 cashback on your next payment")
        notExpense("Hello, how are you")
    }
}
