package database

import (
	"fmt"
	"log"
	"time"

	"github.com/supermarket/models"
	"gorm.io/gorm"
)

// seedEmployees creates employee data
func seedEmployees(tx *gorm.DB, positionMap map[string]uint) (map[string]uint, error) {
	hireDate, _ := time.Parse("2006-01-02", "2024-01-01")

	employees := []models.Employee{
		{
			EmployeeCode: "EMP001",
			FullName:     "Nguyễn Quản Lý",
			PositionID:   positionMap["MGR"],
			Phone:        strPtr("0901111111"),
			Email:        strPtr("manager@supermarket.vn"),
			HireDate:     hireDate,
		},
		{
			EmployeeCode: "EMP002",
			FullName:     "Trần Giám Sát",
			PositionID:   positionMap["SUP"],
			Phone:        strPtr("0902222222"),
			Email:        strPtr("supervisor@supermarket.vn"),
			HireDate:     hireDate.AddDate(0, 0, 14),
		},
		{
			EmployeeCode: "EMP003",
			FullName:     "Lê Thu Ngân",
			PositionID:   positionMap["CASH"],
			Phone:        strPtr("0903333333"),
			Email:        strPtr("cashier1@supermarket.vn"),
			HireDate:     hireDate.AddDate(0, 1, 0),
		},
		{
			EmployeeCode: "EMP004",
			FullName:     "Phạm Bán Hàng",
			PositionID:   positionMap["SALE"],
			Phone:        strPtr("0904444444"),
			Email:        strPtr("sales1@supermarket.vn"),
			HireDate:     hireDate.AddDate(0, 1, 14),
		},
		{
			EmployeeCode: "EMP005",
			FullName:     "Hoàng Thủ Kho",
			PositionID:   positionMap["STOCK"],
			Phone:        strPtr("0905555555"),
			Email:        strPtr("stock1@supermarket.vn"),
			HireDate:     hireDate.AddDate(0, 2, 0),
		},
		{
			EmployeeCode: "EMP006",
			FullName:     "Võ Thu Ngân 2",
			PositionID:   positionMap["CASH"],
			Phone:        strPtr("0906666666"),
			Email:        strPtr("cashier2@supermarket.vn"),
			HireDate:     hireDate.AddDate(0, 2, 15),
		},
	}

	if err := tx.Create(&employees).Error; err != nil {
		return nil, err
	}
	log.Printf("  ✓ Seeded %d employees", len(employees))

	// Return employee ID map
	employeeMap := make(map[string]uint)
	for _, emp := range employees {
		employeeMap[emp.EmployeeCode] = emp.EmployeeID
	}
	return employeeMap, nil
}

// seedCustomers creates customer data
func seedCustomers(tx *gorm.DB, membershipMap map[string]uint) (map[string]uint, error) {
	// Generate 200 customers with realistic data
	firstNames := []string{"Nguyễn", "Trần", "Lê", "Phạm", "Hoàng", "Phan", "Vũ", "Võ", "Đặng", "Bùi",
		"Đỗ", "Hồ", "Ngô", "Dương", "Lý", "Mai", "Cao", "Tôn", "Trịnh", "Nông"}
	middleNames := []string{"Văn", "Thị", "Hoàng", "Minh", "Thúy", "Quốc", "Hữu", "Đức", "Thanh", "Kim",
		"Thu", "Hải", "Anh", "Bảo", "Công", "Duy", "Gia", "Hà", "Hùng", "Khánh"}
	lastNames := []string{"Khách", "Mai", "Nam", "Hằng", "Tuấn", "Linh", "Đức", "Hoa", "Long", "Phương",
		"Quân", "Hương", "Sơn", "Thảo", "Vinh", "Yến", "Bình", "Châu", "Dũng", "Giang",
		"Hiếu", "Khuê", "Loan", "Minh", "Nga", "Phát", "Quỳnh", "Sáng", "Tâm", "Uyên"}

	var customers []models.Customer
	baseRegDate, _ := time.Parse("2006-01-02", "2024-01-01")

	// Distribution: 40% Bronze, 30% Silver, 20% Gold, 8% Platinum, 2% Diamond
	membershipLevels := []string{
		"Bronze", "Bronze", "Bronze", "Bronze", // 40%
		"Silver", "Silver", "Silver", // 30%
		"Gold", "Gold", // 20%
		"Platinum", // 8%
		"Diamond",  // 2%
	}

	for i := 1; i <= 200; i++ {
		// Random name generation
		firstName := firstNames[i%len(firstNames)]
		middleName := middleNames[(i*3)%len(middleNames)]
		lastName := lastNames[(i*7)%len(lastNames)]
		fullName := fmt.Sprintf("%s %s %s", firstName, middleName, lastName)

		// Phone number generation (09xx-xxx-xxx)
		phonePrefix := []string{"090", "091", "092", "093", "094", "095", "096", "097", "098", "099"}
		phone := fmt.Sprintf("%s%07d", phonePrefix[i%len(phonePrefix)], 1000000+(i*12345)%8999999)

		// Email generation
		emailPrefix := fmt.Sprintf("customer%03d", i)
		emailDomains := []string{"gmail.com", "yahoo.com", "hotmail.com", "outlook.com"}
		email := fmt.Sprintf("%s@%s", emailPrefix, emailDomains[i%len(emailDomains)])

		// Membership level based on distribution
		levelIndex := (i - 1) % len(membershipLevels)
		membershipLevel := membershipLevels[levelIndex]

		// Registration date - spread over 8 months
		regDate := baseRegDate.AddDate(0, (i-1)%8, (i*3)%28)

		// Spending and points based on membership level
		var totalSpending float64
		var loyaltyPoints int
		switch membershipLevel {
		case "Bronze":
			totalSpending = float64(500000 + (i*50000)%4500000) // 0.5M - 5M
			loyaltyPoints = int(totalSpending / 10000)
		case "Silver":
			totalSpending = float64(5000000 + (i*100000)%15000000) // 5M - 20M
			loyaltyPoints = int(totalSpending * 1.2 / 10000)
		case "Gold":
			totalSpending = float64(20000000 + (i*500000)%30000000) // 20M - 50M
			loyaltyPoints = int(totalSpending * 1.5 / 10000)
		case "Platinum":
			totalSpending = float64(50000000 + (i*1000000)%50000000) // 50M - 100M
			loyaltyPoints = int(totalSpending * 2.0 / 10000)
		case "Diamond":
			totalSpending = float64(100000000 + (i*2000000)%100000000) // 100M - 200M
			loyaltyPoints = int(totalSpending * 2.5 / 10000)
		}

		customer := models.Customer{
			CustomerCode:      strPtr(fmt.Sprintf("CUST%03d", i)),
			FullName:          strPtr(fullName),
			Phone:             strPtr(phone),
			Email:             strPtr(email),
			MembershipCardNo:  strPtr(fmt.Sprintf("MB%03d", i)),
			MembershipLevelID: uintPtr(membershipMap[membershipLevel]),
			RegistrationDate:  regDate,
			TotalSpending:     totalSpending,
			LoyaltyPoints:     loyaltyPoints,
		}

		customers = append(customers, customer)
	}

	if err := tx.Create(&customers).Error; err != nil {
		return nil, err
	}
	log.Printf("  ✓ Seeded %d customers", len(customers))

	// Return customer ID map
	customerMap := make(map[string]uint)
	for _, customer := range customers {
		if customer.CustomerCode != nil {
			customerMap[*customer.CustomerCode] = customer.CustomerID
		}
	}
	return customerMap, nil
}

// seedEmployeeWorkHours creates employee work hour records
func seedEmployeeWorkHours(tx *gorm.DB, employeeMap map[string]uint) error {
	// Seed work hours for September 2025 (up to 14th)
	// Assuming 8-hour work days, Mon-Sat
	workHours := []models.EmployeeWorkHour{}

	// Generate work hours for first 2 weeks of September 2025
	startDate, _ := time.Parse("2006-01-02", "2025-09-01")
	endDate, _ := time.Parse("2006-01-02", "2025-09-24")

	for date := startDate; !date.After(endDate); date = date.AddDate(0, 0, 1) {
		// Skip Sundays
		if date.Weekday() == time.Sunday {
			continue
		}

		// Morning shift employees (8:00 - 16:00)
		morningShift := []string{"EMP001", "EMP003", "EMP005"} // Manager, Cashier1, Stock1
		for _, empCode := range morningShift {
			empID := employeeMap[empCode]
			checkIn := time.Date(date.Year(), date.Month(), date.Day(), 8, 0, 0, 0, time.Local)
			checkOut := time.Date(date.Year(), date.Month(), date.Day(), 16, 0, 0, 0, time.Local)
			workHours = append(workHours, models.EmployeeWorkHour{
				EmployeeID:   empID,
				WorkDate:     date,
				CheckInTime:  &checkIn,
				CheckOutTime: &checkOut,
				TotalHours:   8.0,
			})
		}

		// Afternoon shift employees (14:00 - 22:00)
		afternoonShift := []string{"EMP002", "EMP004", "EMP006"} // Supervisor, Sales1, Cashier2
		for _, empCode := range afternoonShift {
			empID := employeeMap[empCode]
			checkIn := time.Date(date.Year(), date.Month(), date.Day(), 14, 0, 0, 0, time.Local)
			checkOut := time.Date(date.Year(), date.Month(), date.Day(), 22, 0, 0, 0, time.Local)
			workHours = append(workHours, models.EmployeeWorkHour{
				EmployeeID:   empID,
				WorkDate:     date,
				CheckInTime:  &checkIn,
				CheckOutTime: &checkOut,
				TotalHours:   8.0,
			})
		}
	}

	if err := tx.Create(&workHours).Error; err != nil {
		return err
	}
	log.Printf("  ✓ Seeded %d employee work hour records", len(workHours))
	return nil
}
