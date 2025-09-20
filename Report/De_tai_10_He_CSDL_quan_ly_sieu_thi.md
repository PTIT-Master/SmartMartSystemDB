# Đề tài 10: Xây dựng Hệ CSDL quản lý siêu thị bán lẻ

## Các yêu cầu tối thiểu về CSDL bao gồm

- Thông tin cơ bản về nhân viên, các hàng hóa thuộc các chủng loại
    khác nhau, quầy dựng hàng hóa, nhà cung cấp hàng hóa, kho hàng hóa,
    khách hàng (khách hàng có thẻ thành viên).
- Các nhân viên bán hàng cho khách, và quản lý các hàng hóa.
- Các hàng hóa được lưu trữ trong kho (sau khi nhập hàng), và được bày
    bán trên các quầy hàng. Mỗi quầy hàng chỉ bày bán một số lượng nhất
    định đối với mỗi hàng hóa. Mỗi hàng hóa được bày bán tại một vị trí
    nhất định trên mỗi quầy hàng. Thông tin về số lượng bày bán tối đa
    và vị trí bày bán cho từng sản phẩm trên mỗi quầy hàng cần phải được
    thể hiện trong CSDL. Giá bán hàng hóa phải lớn hơn giá nhập.
- Mỗi quầy hàng chỉ bày bán các hàng hóa thuộc cùng chủng loại (văn
    phòng phẩm, đồ gia dụng, đồ điện tử, đồ bếp, thực phẩm, đồ uống,
    ...).
- Lương của các nhân viên được trả theo từng vị trí, bằng lương cơ bản
    cộng lương theo giờ phục vụ trong siêu thị.
- Học viên nhập đầy đủ dữ liệu cho siêu thị trong khoảng thời gian tối
    thiểu 1 tháng.

## Các yêu cầu tối thiểu về ứng dụng

- Thực hiện các chức năng thêm/xóa/sửa/tìm kiếm các đối tượng trong hệ
    thống như hàng hóa trong kho và hàng hóa trên quầy hàng, khách hàng,
    nhà cung cấp, nhân viên v.v. với các ràng buộc được nêu như trong
    CSDL.
- Chức năng bổ sung hàng hóa vào quầy hàng từ kho. Lượng hàng hóa bổ
    sung vào quầy hàng không được vượt quá số lượng hàng hóa trong kho.
    Khi số lượng hàng hóa tại quầy hàng thấp hơn một ngưỡng thì sẽ hiển
    thị cảnh báo về việc cần bổ sung hàng hóa lên quầy. Khi hàng hóa
    được khách hàng thanh toán, số lượng hàng hóa bán được cập nhật vào
    số lượng hàng hóa sẵn có trên quầy. Tổng số lượng hàng hóa bán thanh
    toán không được vượt quá số hàng hóa sẵn có trên quầy.
- Liệt kê các hàng hóa thuộc một chủng loại nào đó, hoặc thuộc một
    quầy hàng nào đó, sắp xếp theo thứ tự tăng dần số lượng còn lại của
    mỗi hàng hóa đang có trên quầy hàng, hoặc sắp xếp theo số lượng được
    mua trong ngày.
- Liệt kê toàn bộ hàng hóa sắp hết trên quầy (ngưỡng số lượng để xếp
    loại sắp hết tùy từng loại mặt hàng) nhưng vẫn còn trong kho.
- Liệt kê toàn bộ sản phẩm đã hết hàng trong kho nhưng vẫn còn hàng
    trên quầy.
- Liệt kê toàn bộ hàng hóa, sắp xếp theo thứ tự tăng dần số lượng tổng
    trên quầy lẫn trong kho.
- Liệt kê hàng hóa, sắp xếp theo thứ tự giảm dần doanh thu của từng
    hàng hóa trong một tháng cụ thể.
- Tìm thông tin của các hàng hóa đã quá hạn bán. Hạn bán hàng của mỗi
    hàng hóa được xác định bằng số ngày từ lúc nhập kho đến thời điểm
    hiện tại trừ đi hạn sử dụng của mỗi hàng hóa. Các hàng hóa quá hạn
    sử dụng cần phải được loại bỏ khỏi danh sách hàng hóa mới còn hạn sử
    dụng.
- Cập nhật giá bán của các hàng hóa khi đến hạn bán. Mỗi loại hàng hóa
    có quy tắc giảm giá khác nhau, ví dụ: Tương ứng với số ngày còn hạn
    dưới 5 ngày thì giảm 50%, nhưng các loại rau quả thì phải dưới 3
    ngày mới giảm 50%.
- Hiện thị thông tin của các khách hàng thành viên thiết và các hóa
    đơn của các khách hàng dựa trên thông tin dữ liệu của các khách hàng
    này.
- Thống kê doanh thu của các sản phẩm và xếp hạng mặt hàng dựa trên
    doanh số bán hàng trong hệ thống.
- Thống kê doanh thu của các nhà cung cấp và xếp hạng các nhà cung cấp
    dựa trên tổng doanh thu từ hàng hóa của các nhà cung cấp đó.
- Các ràng buộc số lượng cần ghi trong CSDL cũng cần phải được thể
    hiện trong ứng dụng.
