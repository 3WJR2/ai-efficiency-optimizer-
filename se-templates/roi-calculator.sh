#!/bin/bash

# Qodo ROI Calculator for Solutions Engineers
# Quick command-line ROI calculation for customer conversations

echo "==============================================="
echo "   Qodo ROI Calculator"
echo "==============================================="
echo ""

# Get customer inputs
read -p "Company name: " company_name
read -p "Number of developers: " num_devs
read -p "Average developer annual salary ($): " avg_salary
echo ""

echo "Time spent on code quality activities:"
read -p "  % of time on PR reviews: " pr_review_pct
read -p "  % of time writing tests: " test_writing_pct
read -p "  % of time fixing bugs: " bug_fixing_pct
echo ""

read -p "Current test coverage (%): " current_coverage
read -p "Production bugs per month: " bugs_per_month
read -p "Average cost per production bug ($): " bug_cost
echo ""

read -p "Qodo annual cost ($): " qodo_cost
echo ""

# Calculations
total_dev_cost=$(echo "$num_devs * $avg_salary" | bc)

# Time savings with Qodo
pr_time_saved=0.70  # 70% reduction in PR review time
test_time_saved=0.60  # 60% reduction in test writing time
bug_time_saved=0.40  # 40% reduction in bug fixing time

# Calculate annual time costs
pr_annual_cost=$(echo "$total_dev_cost * ($pr_review_pct / 100)" | bc)
test_annual_cost=$(echo "$total_dev_cost * ($test_writing_pct / 100)" | bc)
bug_annual_cost=$(echo "$total_dev_cost * ($bug_fixing_pct / 100)" | bc)

# Calculate savings
pr_savings=$(echo "$pr_annual_cost * $pr_time_saved" | bc)
test_savings=$(echo "$test_annual_cost * $test_time_saved" | bc)
bug_time_savings=$(echo "$bug_annual_cost * $bug_time_saved" | bc)

# Bug cost savings (30% reduction in production bugs)
bug_reduction=0.30
bugs_saved=$(echo "$bugs_per_month * 12 * $bug_reduction" | bc)
bug_cost_savings=$(echo "$bugs_saved * $bug_cost" | bc)

# Total savings
total_savings=$(echo "$pr_savings + $test_savings + $bug_time_savings + $bug_cost_savings" | bc)

# ROI calculation
net_benefit=$(echo "$total_savings - $qodo_cost" | bc)
roi_pct=$(echo "scale=1; ($net_benefit / $qodo_cost) * 100" | bc)
payback_months=$(echo "scale=1; ($qodo_cost / $total_savings) * 12" | bc)

# Calculate new metrics with Qodo
new_coverage=$(echo "$current_coverage + 25" | bc)
if (( $(echo "$new_coverage > 90" | bc -l) )); then
    new_coverage=90
fi

new_bugs=$(echo "$bugs_per_month * (1 - $bug_reduction)" | bc)

# Print results
echo ""
echo "==============================================="
echo "   ROI ANALYSIS: $company_name"
echo "==============================================="
echo ""
echo "CURRENT STATE:"
echo "  Team size: $num_devs developers"
echo "  Annual labor cost: \$$(printf "%'d" $total_dev_cost)"
echo "  Test coverage: ${current_coverage}%"
echo "  Production bugs: $bugs_per_month/month"
echo ""
echo "TIME COST BREAKDOWN:"
echo "  PR reviews: \$$(printf "%'.0f" $pr_annual_cost)/year (${pr_review_pct}% of time)"
echo "  Test writing: \$$(printf "%'.0f" $test_annual_cost)/year (${test_writing_pct}% of time)"
echo "  Bug fixing: \$$(printf "%'.0f" $bug_annual_cost)/year (${bug_fixing_pct}% of time)"
echo ""
echo "QODO IMPACT:"
echo "  PR review time saved: ${pr_time_saved}% = \$$(printf "%'.0f" $pr_savings)/year"
echo "  Test writing time saved: ${test_time_saved}% = \$$(printf "%'.0f" $test_savings)/year"
echo "  Bug fixing time saved: ${bug_time_saved}% = \$$(printf "%'.0f" $bug_time_savings)/year"
echo "  Production bugs prevented: ${bug_reduction}% = \$$(printf "%'.0f" $bug_cost_savings)/year"
echo ""
echo "FINANCIAL SUMMARY:"
echo "  Total annual savings: \$$(printf "%'.0f" $total_savings)"
echo "  Qodo annual cost: \$$(printf "%'.0f" $qodo_cost)"
echo "  Net benefit: \$$(printf "%'.0f" $net_benefit)"
echo ""
echo "  ROI: $(printf "%.0f" $roi_pct)%"
echo "  Payback period: $(printf "%.1f" $payback_months) months"
echo ""
echo "NEW METRICS WITH QODO:"
echo "  Test coverage: ${current_coverage}% → ${new_coverage}% (+$(echo "$new_coverage - $current_coverage" | bc) points)"
echo "  Production bugs: $bugs_per_month/month → $(printf "%.1f" $new_bugs)/month (-${bug_reduction}%)"
echo "  Time to merge: -70% faster"
echo "  Developer satisfaction: +35% average increase"
echo ""
echo "==============================================="
echo "   ELEVATOR PITCH"
echo "==============================================="
echo ""
echo "\"By investing \$$(printf "%'d" $qodo_cost) in Qodo, your team of"
echo "$num_devs developers will save \$$(printf "%'d" $total_savings) annually"
echo "through faster reviews, automated testing, and fewer"
echo "production bugs. That's a $(printf "%.0f" $roi_pct)% ROI with payback in"
echo "$(printf "%.1f" $payback_months) months. Plus, your test coverage improves"
echo "to ${new_coverage}% and production bugs drop by ${bug_reduction}%.\""
echo ""
echo "==============================================="

# Offer to save
echo ""
read -p "Save this analysis? (y/n): " save_choice
if [[ "$save_choice" == "y" || "$save_choice" == "Y" ]]; then
    filename="${company_name// /_}_roi_$(date +%Y%m%d).txt"
    {
        echo "==============================================="
        echo "   ROI ANALYSIS: $company_name"
        echo "   Generated: $(date)"
        echo "==============================================="
        echo ""
        echo "INPUTS:"
        echo "  Developers: $num_devs"
        echo "  Avg salary: \$$avg_salary"
        echo "  PR review time: ${pr_review_pct}%"
        echo "  Test writing time: ${test_writing_pct}%"
        echo "  Bug fixing time: ${bug_fixing_pct}%"
        echo "  Current coverage: ${current_coverage}%"
        echo "  Production bugs: $bugs_per_month/month"
        echo "  Bug cost: \$$bug_cost"
        echo "  Qodo cost: \$$qodo_cost"
        echo ""
        echo "RESULTS:"
        echo "  Total savings: \$$(printf "%'.0f" $total_savings)"
        echo "  Net benefit: \$$(printf "%'.0f" $net_benefit)"
        echo "  ROI: $(printf "%.0f" $roi_pct)%"
        echo "  Payback: $(printf "%.1f" $payback_months) months"
        echo ""
        echo "IMPROVEMENTS:"
        echo "  Coverage: ${current_coverage}% → ${new_coverage}%"
        echo "  Bugs: $bugs_per_month/mo → $(printf "%.1f" $new_bugs)/mo"
    } > "$filename"
    echo "Saved to: $filename"
fi

echo ""
echo "Done!"
